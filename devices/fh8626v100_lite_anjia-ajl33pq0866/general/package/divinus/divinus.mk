################################################################################
#
# divinus — ANJIA AJL33PQ0866 device package
#
################################################################################

# The generic firmware keeps upstream Divinus. This device package selects the
# one-commit generic FH8626 port and applies the camera-only feature patch.
DIVINUS_SITE = $(call github,openipc,divinus,$(DIVINUS_VERSION))
DIVINUS_VERSION = 8d400262898e8e82df6171fde7e8911ec7930249
DIVINUS_LICENSE = MIT
DIVINUS_LICENSE_FILES = LICENSE

ifeq ($(BR2_TOOLCHAIN_USES_GLIBC),y)
	DIVINUS_OPTIONS = "-rdynamic -s -Os -lm"
else
	DIVINUS_OPTIONS = "-rdynamic -s -Os"
endif

define DIVINUS_BUILD_CMDS
	$(MAKE) CC=$(TARGET_CC) OPT=$(DIVINUS_OPTIONS) -C $(@D)/src
endef

define DIVINUS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(@D)/divinus.yaml

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/divinus
endef

$(eval $(generic-package))
