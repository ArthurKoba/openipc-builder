# FH8626V100 ANJIA AJL33PQ0866 clean device profile

This branch reconstructs the named ANJIA profile as a thin Builder layer on top
of the clean FH8626V100 Firmware/Linux split.

Cross-repository staging dependencies:

- Firmware core: `ArthurKoba/openipc-firmware/work/fh8626v100@eabd1ccd4684af6997771269c4655f7e4435bcec`;
- Linux: `ArthurKoba/openipc-linux/work/fh8626v100@357c2d13e7589db0dbe2bbf89c2ec38b1c036e6e`;
- Divinus implementation: `ArthurKoba/openipc-divinus/work/fh8626v100@1e624bd5aca97ba772413d2b00a10314d1db039f`; it is selected by this device defconfig but is not patched or copied here.

The profile keeps only named-device deltas: the ANJIA kernel fragment, RTL8188FU
selection, microSD policy, device GPIO/illumination configuration and
source-built PTZ/lens support.

The one-bit SD0 slot is selected through the hardware-oriented kernel symbol:

`CONFIG_FH8626V100_SD0_1BIT=y`

The historical retail-named symbol
`CONFIG_FH8626V100_AJL33PQ0866_MMC` is not used.

This branch intentionally contains no generic FH8626 kernel config, no FH8626
kernel patch directory, no factory `.ko/.so/.bin` payloads and no Divinus source
or patch. Those belong respectively to Firmware/Linux, evidence/provenance work
and Divinus.

The exact Linux tarball URL is a temporary engineering pin to the ArthurKoba
fork until the curated series lands in `OpenIPC/linux`. `builder.sh` supports
`OPENIPC_FW_REPO` and `OPENIPC_FW_REV`, so this staging profile can be built
against the fork-local Firmware core without copying generic FH8626 code into
Builder. The ordinary no-override path still clones upstream `OpenIPC/firmware`.

The device remains temporarily listed in Builder CI `NOT_BUILT` because normal
CI does not consume the fork-local Firmware core. Remove that opt-out only when
the required Firmware state is available through the normal CI clone path.

No build or hardware acceptance is implied by this source-only staging profile.
