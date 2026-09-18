# FH8626V100 ANJIA AJL33PQ0866 clean device profile

This branch reconstructs the named ANJIA profile as a thin Builder layer on top
of the clean FH8626V100 Firmware/Linux split.

Cross-repository staging dependencies:

- Firmware: `ArthurKoba/openipc-firmware/rework/fh8626v100-clean-integration@f9146dd42a2f606d305ebccd301268848de26880`;
- Linux: `ArthurKoba/openipc-linux/rework/fh8626v100-final-series@357c2d13e7589db0dbe2bbf89c2ec38b1c036e6e`;
- Divinus implementation remains owned by the Divinus repository and is not
  patched or copied here.

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
fork until the curated series lands in `OpenIPC/linux`. The default Builder
workflow still clones `OpenIPC/firmware`; therefore this staging profile becomes
directly buildable through the normal Builder path only after the clean Firmware
integration is available from the Firmware source Builder consumes.

The device is temporarily listed in Builder CI `NOT_BUILT` for the same cross-repository reason; remove that opt-out when the required Firmware base is available through the normal Builder clone.

No build or hardware acceptance is implied by this source-only staging profile.
