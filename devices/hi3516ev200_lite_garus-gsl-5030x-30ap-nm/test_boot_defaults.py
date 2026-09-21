#!/usr/bin/env python3
"""Host-only GARUS profile checks; no camera access, downloads or compilation.

Python 3.8+ and BusyBox required. --stripper tests the exact packaged shell too.
Optional --firmware checks exclusions against a pinned firmware source checkout;
--kernel-config and --rootfs validate real build outputs when they exist.
"""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile

PROFILE = Path(__file__).resolve().parent
TARGET = PROFILE.name
FRAGMENT = 'br-ext-chip-hisilicon/board/hi3516ev200/garus-gsl-5030x-30ap-nm.fragment'
KEEP = {'/usr/lib/sensors/libsns_sc2315e.so',
        '/etc/sensors/sc2315e_i2c_1080p.ini',
        '/etc/sensors/iq/default.ini', '/etc/sensors/iq/imx307.ini'}
DISABLED_PACKAGES = ('MAJESTIC_AF', 'MOTORS', 'WIREGUARD_LINUX_COMPAT',
                     'WIREGUARD_TOOLS', 'VTUND_OPENIPC')
REQUIRED_KERNEL = ('MTD_SPI_NOR', 'SPI_HISI_SFC', 'MFD_HISI_FMC', 'HISI_FEMAC',
                   'MDIO_HISI_FEMAC', 'I2C_CHARDEV', 'I2C_HIBVT', 'GPIO_PL061',
                   'GPIO_SYSFS', 'DEVMEM', 'SERIAL_AMBA_PL011_CONSOLE',
                   'SQUASHFS', 'SQUASHFS_XZ', 'JFFS2_FS', 'BLK_DEV_INITRD')
EXPECTED = {
    '.isp.sensorConfig': '/etc/sensors/sc2315e_i2c_1080p.ini',
    '.video0.enabled': 'true', '.video0.codec': 'h264',
    '.video0.size': '1920x1080', '.video0.fps': '20', '.video0.bitrate': '4096',
    '.video1.enabled': 'false',
    '.audio.enabled': 'false', '.audio.outputEnabled': 'false',
    '.nightMode.lightMonitor': 'true', '.nightMode.lightSensorPin': '15',
    '.nightMode.lightSensorInvert': 'false', '.nightMode.irCutEnabled': 'true',
    '.nightMode.irCutPin1': '8', '.nightMode.irCutPin2': '9',
    '.nightMode.colorToGray': 'true', '.nightMode.backlightEnabled': 'false',
}
MOCK = '''import json, os, sys
from pathlib import Path
p = Path(os.environ["GARUS_MOCK_STATE"])
s = json.loads(p.read_text())
name, args = Path(sys.argv[0]).name, sys.argv[1:]
s["calls"].append([name] + args)
rc, output = 0, ""
if name == "ipcinfo":
    assert args == ["-c"], args
    output = s.get("soc", "hi3516ev200")
elif name == "devmem":
    assert len(args) in (2, 3) and args[1] == "32", args
    addr = args[0]
    assert addr in s["regs"], "unexpected MMIO address: " + addr
    op = "read" if len(args) == 2 else "write"
    if s.get("fail") == op + ":" + addr:
        rc = 1
    elif op == "read":
        output = s.get("invalid_read", "0x%08x" % s["regs"][addr])
    elif s.get("ignore_write") != addr:
        s["regs"][addr] = int(args[2], 0)
elif name == "fw_setenv":
    assert args == ["sensor", "sc2315e"], args
    rc = int(s.get("fail_command") == name)
elif name == "cli":
    assert len(args) == 3 and args[0] == "-s", args
    rc = int(s.get("fail_command") == "cli:" + args[1])
else:
    raise AssertionError("unexpected command: " + name)
p.write_text(json.dumps(s))
if output:
    print(output)
sys.exit(rc)
'''


def config(path):
    result = {}
    for line in path.read_text().splitlines():
        disabled = re.fullmatch(r'# ((?:BR2|CONFIG)_[A-Za-z0-9_]+) is not set', line)
        if disabled:
            key, value = disabled[1], 'n'
        elif re.match(r'(BR2|CONFIG)_[A-Za-z0-9_]+=', line):
            key, value = line.split('=', 1)
        else:
            continue
        assert key not in result, 'duplicate symbol: ' + key
        result[key] = value
    return result


def profile_checks(args):
    d = config(PROFILE / 'br-ext-chip-hisilicon/configs' / (TARGET + '_defconfig'))
    for suffix in DISABLED_PACKAGES:
        assert d.get('BR2_PACKAGE_' + suffix) == 'n', suffix
    for suffix in ('MAJESTIC', 'MAJESTIC_WEBUI', 'MAJESTIC_FONTS', 'DROPBEAR_OPENIPC',
                   'UBOOT_TOOLS', 'YAML_CLI', 'IPCTOOL', 'HISILICON_OPENSDK',
                   'HISILICON_OSDRV_HI3516EV200', 'LIBOGG_OPENIPC', 'OPUS_OPENIPC'):
        assert d.get('BR2_PACKAGE_' + suffix) == 'y', suffix
    assert d['BR2_OPENIPC_FLASH_SIZE'] == '"8"'
    assert d['BR2_OPENIPC_SOC_MODEL'] == '"hi3516ev200"'
    assert d['BR2_OPENIPC_VARIANT'] == '"lite"'
    assert d['BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES'] == (
        '"$(EXTERNAL_VENDOR)/board/$(OPENIPC_SOC_FAMILY)/garus-gsl-5030x-30ap-nm.fragment"')
    fragment = config(PROFILE / FRAGMENT)
    assert fragment and set(fragment.values()) == {'n'}
    assert not set('CONFIG_' + n for n in REQUIRED_KERNEL) & fragment.keys()
    entries = [s for s in (PROFILE / 'general/scripts/excludes/hi3516ev200_lite.list')
               .read_text().splitlines() if s and not s.startswith('#')]
    assert len(entries) == len(set(entries)), 'duplicate exclusion'
    for entry in entries:
        assert entry.startswith('/') and '..' not in PurePosixPath(entry).parts
        assert not any(c in entry for c in '*?[] \t'), 'not a literal path: ' + entry
        assert entry not in KEEP, 'required runtime data excluded: ' + entry
        assert (entry.startswith(('/etc/sensors/', '/usr/lib/sensors/')) or
                entry in ('/usr/bin/ircut_demo', '/lib/modules/4.9.37/hisilicon/camhi-motor.ko'))
    assert len([s for s in entries if s.startswith('/usr/lib/sensors/')]) == 33
    assert '/etc/sensors/iq/imx335.ini' in entries
    print('profile: package intent, fragment wiring, literal pruning and IQ preservation OK')

    if args.firmware:
        fw = args.firmware
        osdrv = fw / 'general/package/hisilicon-osdrv-hi3516ev200/files'
        mk = (fw / 'general/package/hisilicon-opensdk/hisilicon-opensdk.mk').read_text()
        section = mk.split('HISILICON_OPENSDK_SENSORS_hi3516ev200 =', 1)[1].split('\n\n', 1)[0]
        supplied = {'/usr/lib/sensors/' + p.name for p in (osdrv / 'sensor').glob('*.so')}
        supplied |= {'/usr/lib/sensors/' + name + '.so'
                     for name in re.findall(r'/((?:libsns_)[A-Za-z0-9_]+)', section)}
        supplied |= {'/etc/sensors/' + p.relative_to(osdrv / 'sensor/config').as_posix()
                     for p in (osdrv / 'sensor/config').rglob('*.ini')}
        supplied |= {'/etc/sensors/iq/' + n for n in ('default.ini', 'imx307.ini', 'imx335.ini', 'f23.ini')}
        assert (osdrv / 'script/ircut_demo').is_file()
        assert (osdrv / 'kmod/camhi-motor.ko').is_file()
        supplied |= {'/usr/bin/ircut_demo', '/lib/modules/4.9.37/hisilicon/camhi-motor.ko'}
        assert set(entries) <= supplied, 'stale exclusions: ' + str(set(entries) - supplied)
        assert supplied - set(entries) == KEEP, 'new/unaccounted sensor data: ' + str(supplied - set(entries) - KEEP)
        print('firmware source inventory: all exclusions exist; only selected sensor and IQ data retained')
    if args.kernel_config:
        resolved = config(args.kernel_config)
        for key in fragment:
            assert resolved.get(key, 'n') == 'n', 'fragment not applied: ' + key
        for name in REQUIRED_KERNEL:
            assert resolved.get('CONFIG_' + name) == 'y', 'required kernel feature lost: ' + name
        print('resolved kernel config: disabled peripherals and required boot/camera features OK')
    if args.rootfs:
        tree = args.rootfs.resolve()
        for entry in entries:
            path = tree / entry.lstrip('/')
            assert not path.exists() and not path.is_symlink(), 'excluded file survived: ' + entry
        for entry in KEEP:
            path = tree / entry.lstrip('/')
            assert path.is_file(), 'missing runtime data: ' + entry
            assert tree in path.resolve().parents, 'symlink escaped rootfs: ' + entry
        assert (tree / 'etc/sensors/iq/default.ini').resolve() == (tree / 'etc/sensors/iq/imx307.ini').resolve()
        assert {p.name for p in (tree / 'usr/lib/sensors').glob('*.so')} == {'libsns_sc2315e.so'}
        for name in ('customizer.sh', 'muxes.sh'):
            assert (tree / 'usr/share/openipc' / name).is_file(), name
        print('built rootfs: pruned paths absent, selected sensor, IQ link and hooks present')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stripper', 'firmware', 'kernel-config', 'rootfs'):
        parser.add_argument('--' + name, type=Path)
    args = parser.parse_args()
    if not __debug__:
        parser.error('do not use python -O: this test uses assertions')
    busybox = shutil.which('busybox')
    if not busybox:
        parser.error('BusyBox is required')
    profile_checks(args)
    overlay = PROFILE / 'general/overlay/usr/share/openipc'
    scripts = {n: overlay / (n + '.sh') for n in ('customizer', 'muxes')}
    cases = 0
    with tempfile.TemporaryDirectory(prefix='garus-host-test-') as temp:
        work = Path(temp)
        mock = work / 'mock'
        mock.write_text('#!' + sys.executable + ' -S\n' + MOCK)
        mock.chmod(0o755)
        for command in ('ipcinfo', 'devmem', 'cli', 'fw_setenv'):
            (work / command).symlink_to(mock)
        state_path = work / 'state.json'
        # No fallback to host commands: an unexpected command must fail.
        env = dict(os.environ, PATH=str(work), GARUS_MOCK_STATE=str(state_path))
        variants = [('source', scripts)]
        if args.stripper:
            stripped = {}
            for name, script in scripts.items():
                dest = work / (name + '-stripped.sh')
                result = subprocess.run(['awk', '-f', str(args.stripper), str(script)],
                                        check=True, text=True, capture_output=True)
                dest.write_text(result.stdout)
                stripped[name] = dest
            variants.append(('packaged', stripped))

        def run(script, state, success=True):
            state_path.write_text(json.dumps(state))
            result = subprocess.run([busybox, 'ash', str(script)], env=env,
                                    text=True, capture_output=True, timeout=10)
            assert (result.returncode == 0) == success, (script, result.returncode, result.stderr)
            return json.loads(state_path.read_text())

        def initial(direction=0xa5, mux=0x1001, **extra):
            return dict(regs={'0x120B1400': direction, '0x120C001C': mux}, calls=[], **extra)

        def writes(state):
            return [c for c in state['calls'] if c[0] == 'devmem' and len(c) == 4]

        for variant, paths in variants:
            for script in paths.values():
                subprocess.run([busybox, 'ash', '-n', str(script)], check=True)
            for direction, mux in ((0xff, 0x1001), (0x25, 0x1c02), (0xffffffff, 0xa5a5ffff)):
                state = run(paths['muxes'], initial(direction, mux))
                assert state['regs'] == {'0x120B1400': direction & ~0x80,
                                         '0x120C001C': (mux & ~0xf) | 2}
                if direction & 0x80:
                    assert writes(state)[0][1] == '0x120B1400', 'input must precede mux'
                state['calls'] = []
                state = run(paths['muxes'], state)
                assert not writes(state), 'idempotent second boot'
                cases += 1
            state = run(paths['muxes'], initial(soc='hi3516ev300'), success=False)
            assert not any(c[0] == 'devmem' for c in state['calls'])
            cases += 1
            for option in ({'fail': 'read:0x120B1400'}, {'fail': 'write:0x120B1400'},
                           {'ignore_write': '0x120B1400'}, {'invalid_read': 'not-hex'},
                           {'invalid_read': '0x'}, {'invalid_read': '0x100000000'}):
                state = run(paths['muxes'], initial(**option), success=False)
                assert not any(c[1] == '0x120C001C' for c in writes(state))
                cases += 1
            for option in ({'fail': 'read:0x120C001C'}, {'fail': 'write:0x120C001C'},
                           {'ignore_write': '0x120C001C'}):
                run(paths['muxes'], initial(**option), success=False)
                cases += 1
            state = run(paths['customizer'], initial())
            actual = {}
            for call in state['calls']:
                if call[0] == 'cli':
                    assert len(call) == 4 and call[1] == '-s'
                    assert re.fullmatch(r'(\.[A-Za-z][A-Za-z0-9]*)+', call[2]), call
                    assert call[2] not in actual, 'duplicate default'
                    actual[call[2]] = call[3]
                else:
                    assert call == ['fw_setenv', 'sensor', 'sc2315e'], call
            assert actual == EXPECTED, actual
            cases += 1
            state = run(paths['customizer'], initial(fail_command='fw_setenv'), success=False)
            assert state['calls'] == [['fw_setenv', 'sensor', 'sc2315e']]
            cases += 1
            state = run(paths['customizer'], initial(fail_command='cli:.video0.size'), success=False)
            assert state['calls'][-1] == ['cli', '-s', '.video0.size', '1920x1080']
            cases += 1
            print(variant + ': ash syntax, RMW/preservation, idempotency, failure paths and 1080p/video-only defaults OK')
    print(str(cases) + ' host cases passed; NOT a firmware build or hardware acceptance')


if __name__ == '__main__':
    main()
