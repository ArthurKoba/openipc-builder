################################################################################
#
# majestic-fh8852v200-compat
#
################################################################################

MAJESTIC_FH8852V200_COMPAT_VERSION = master
MAJESTIC_FH8852V200_COMPAT_SITE = https://openipc.s3-eu-west-1.amazonaws.com
MAJESTIC_FH8852V200_COMPAT_SOURCE = majestic.fh8852v200.lite.master.tar.bz2
MAJESTIC_FH8852V200_COMPAT_LICENSE = PROPRIETARY
MAJESTIC_FH8852V200_COMPAT_LICENSE_FILES = LICENSE
MAJESTIC_FH8852V200_COMPAT_DEPENDENCIES = json-c libevent-openipc libogg-openipc libyaml mbedtls-openipc opus-openipc

MAJESTIC_FH8852V200_COMPAT_VENDOR_LIBDIR = $(BR2_EXTERNAL_GENERAL_PATH)/package/fullhan-osdrv-fh8852v200/files/lib

define MAJESTIC_FH8852V200_COMPAT_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 $(@D)/majestic $(TARGET_DIR)/usr/bin/majestic
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 $(@D)/majestic.yaml $(TARGET_DIR)/etc/majestic.yaml
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib/majestic-fh8852v200
	$(INSTALL) -m 644 $(MAJESTIC_FH8852V200_COMPAT_VENDOR_LIBDIR)/*.so $(TARGET_DIR)/usr/lib/majestic-fh8852v200/
	$(INSTALL) -m 755 $(BR2_EXTERNAL_GENERAL_PATH)/package/majestic-fh8852v200-compat/files/majestic-fh8852v200-run $(TARGET_DIR)/usr/bin/majestic-fh8852v200-run
endef

$(eval $(generic-package))
