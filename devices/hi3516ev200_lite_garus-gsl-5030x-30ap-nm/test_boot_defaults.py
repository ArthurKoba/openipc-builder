#!/usr/bin/env python3
"""Host-only GPIO15/defaults regression checks; never access real camera MMIO.

Run with Python 3.8+ and BusyBox on the host. An optional --stripper points to
firmware/general/scripts/strip-shell-comments.awk to also test packaged scripts.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

MOCK = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ["GARUS_MOCK_STATE"])
s = json.loads(p.read_text())
name = Path(sys.argv[0]).name
args = sys.argv[1:]
s["calls"].append([name] + args)
rc, output = 0, ""
if name == "ipcinfo":
    assert args == ["-c"], args
    output = s.get("soc", "hi3516ev200")
elif name == "devmem":
    assert args[1] == "32", args
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
elif name != "cli":
    raise AssertionError("unexpected command: " + name)
p.write_text(json.dumps(s))
if output:
    print(output)
sys.exit(rc)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stripper', type=Path)
    args = parser.parse_args()
    busybox = shutil.which('busybox')
    if not busybox:
        parser.error('BusyBox is required for ash checks')
    overlay = Path(__file__).resolve().parent / 'general/overlay/usr/share/openipc'
    scripts = {n: overlay / (n + '.sh') for n in ('customizer', 'muxes')}
    cases = 0
    with tempfile.TemporaryDirectory(prefix='garus-host-test-') as temp:
        work = Path(temp)
        mock = work / 'mock'
        mock.write_text("#!" + sys.executable + " -S\n" + MOCK.partition("\n")[2])
        mock.chmod(0o755)
        for command in ('ipcinfo', 'devmem', 'cli', 'fw_setenv'):
            (work / command).symlink_to(mock)
        state_path = work / 'state.json'
        env = dict(os.environ, PATH=str(work) + os.pathsep + os.environ['PATH'],
                   GARUS_MOCK_STATE=str(state_path))
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
            assert (result.returncode == 0) == success, result.stderr
            return json.loads(state_path.read_text())

        def initial(direction=0xa5, mux=0x1001, **extra):
            return dict(regs={'0x120B1400': direction, '0x120C001C': mux},
                        calls=[], **extra)

        def writes(state):
            return [c for c in state['calls'] if c[0] == 'devmem' and len(c) == 4]

        expected = {
            '.audio.enabled': 'false', '.audio.outputEnabled': 'false',
            '.nightMode.lightMonitor': 'true', '.nightMode.lightSensorPin': '15',
            '.nightMode.lightSensorInvert': 'false', '.nightMode.irCutEnabled': 'true',
            '.nightMode.irCutPin1': '8', '.nightMode.irCutPin2': '9',
            '.nightMode.colorToGray': 'true', '.nightMode.backlightEnabled': 'false',
        }
        for variant, paths in variants:
            for script in paths.values():
                subprocess.run([busybox, 'ash', '-n', str(script)], check=True)
            for direction, mux in ((0xff, 0x1001), (0x25, 0x1c02),
                                   (0xffffffff, 0xa5a5ffff)):
                state = run(paths['muxes'], initial(direction, mux))
                assert state['regs'] == {'0x120B1400': direction & ~0x80,
                                         '0x120C001C': (mux & ~0xf) | 2}
                if direction & 0x80:
                    assert writes(state)[0][1] == '0x120B1400', 'input must precede mux'
                state['calls'] = []
                state = run(paths['muxes'], state)
                assert not writes(state), 'second boot must need no duplicate MMIO writes'
                cases += 1
            state = run(paths['muxes'], initial(soc='hi3516ev300'), success=False)
            assert not any(c[0] == 'devmem' for c in state['calls'])
            cases += 1
            for option in ({'fail': 'read:0x120B1400'},
                           {'fail': 'write:0x120B1400'},
                           {'ignore_write': '0x120B1400'},
                           {'invalid_read': 'not-hex'}):
                state = run(paths['muxes'], initial(**option), success=False)
                assert not any(c[1] == '0x120C001C' for c in writes(state))
                cases += 1
            for option in ({'fail': 'read:0x120C001C'},
                           {'fail': 'write:0x120C001C'},
                           {'ignore_write': '0x120C001C'}):
                run(paths['muxes'], initial(**option), success=False)
                cases += 1
            state = run(paths['customizer'], initial())
            actual = {}
            for call in state['calls']:
                if call[0] == 'cli':
                    assert call[1] == '-s' and len(call) == 4, call
                    actual[call[2]] = call[3]
                else:
                    assert call == ['fw_setenv', 'sensor', 'sc2315e'], call
            assert actual == expected, actual
            cases += 1
            print(variant + ': ash syntax, masked writes, preservation, idempotency, '
                  'SoC guard, failure paths and video-only defaults OK')
    print(str(cases) + ' host cases passed; not a firmware build or hardware acceptance')


if __name__ == '__main__':
    main()
