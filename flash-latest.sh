#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE="${1:-hi3516cv200_lite_spezvision-svi-252b-k202}"
CAMERA_IP="${2:-192.168.1.224}"
ARCHIVE_ROOT="${ROOT_DIR}/archive/${DEVICE}"

if [[ ! -d "${ARCHIVE_ROOT}" ]]; then
    echo "Archive directory not found: ${ARCHIVE_ROOT}" >&2
    exit 1
fi

LATEST_NAME="$(find "${ARCHIVE_ROOT}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort | tail -n 1)"
if [[ -z "${LATEST_NAME}" ]]; then
    echo "No assembled firmware found under: ${ARCHIVE_ROOT}" >&2
    exit 1
fi

LATEST_DIR="${ARCHIVE_ROOT}/${LATEST_NAME}"
KERNEL="${LATEST_DIR}/uImage.hi3516cv200"
ROOTFS="${LATEST_DIR}/rootfs.squashfs.hi3516cv200"

for image in "${KERNEL}" "${ROOTFS}"; do
    if [[ ! -s "${image}" ]]; then
        echo "Required image missing or empty: ${image}" >&2
        exit 1
    fi
done

echo "Using latest build: ${LATEST_DIR}"
stat -c '%n %s bytes' "${KERNEL}" "${ROOTFS}"
sha256sum "${KERNEL}" "${ROOTFS}"

CONTROL_PATH="$(mktemp -u /tmp/openipc-flash-XXXXXX.sock)"
cleanup() {
    ssh -S "${CONTROL_PATH}" -O exit "root@${CAMERA_IP}" >/dev/null 2>&1 || true
    rm -f "${CONTROL_PATH}"
}
trap cleanup EXIT

echo "Opening SSH connection to root@${CAMERA_IP} ..."
ssh -MNf -o ControlMaster=yes -o ControlPersist=120 -o ControlPath="${CONTROL_PATH}" "root@${CAMERA_IP}"

echo "Uploading kernel and rootfs ..."
scp -O -o ControlPath="${CONTROL_PATH}" "${KERNEL}" "${ROOTFS}" "root@${CAMERA_IP}:/tmp/"

echo "Starting clean sysupgrade (-n -z) ..."
set +e
ssh -o ControlPath="${CONTROL_PATH}" "root@${CAMERA_IP}" \
    'test -s /tmp/uImage.hi3516cv200 && test -s /tmp/rootfs.squashfs.hi3516cv200 && echo OPENIPC_SYSUPGRADE_START && sysupgrade --kernel=/tmp/uImage.hi3516cv200 --rootfs=/tmp/rootfs.squashfs.hi3516cv200 -n -z'
SSH_RC=$?
set -e

if [[ ${SSH_RC} -eq 0 ]]; then
    echo "sysupgrade command completed. Watch UART for reboot/boot log."
elif [[ ${SSH_RC} -eq 255 ]]; then
    echo "SSH connection closed during reboot; this is expected after sysupgrade. Watch UART."
else
    echo "Remote sysupgrade failed with ssh exit code ${SSH_RC}." >&2
    exit "${SSH_RC}"
fi
