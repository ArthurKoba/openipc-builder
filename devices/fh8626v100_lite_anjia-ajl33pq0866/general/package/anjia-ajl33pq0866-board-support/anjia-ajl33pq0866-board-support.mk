################################################################################
#
# anjia-ajl33pq0866-board-support
#
################################################################################

ANJIA_AJL33PQ0866_BOARD_SUPPORT_SITE_METHOD = local
ANJIA_AJL33PQ0866_BOARD_SUPPORT_SITE = $(ANJIA_AJL33PQ0866_BOARD_SUPPORT_PKGDIR)/src

define ANJIA_AJL33PQ0866_BOARD_SUPPORT_BUILD_CMDS
	$(MAKE) CC="$(TARGET_CC)" CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D)
endef

define ANJIA_AJL33PQ0866_BOARD_SUPPORT_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/fh8626-ptz \
		$(TARGET_DIR)/usr/sbin/fh8626-ptz
	$(INSTALL) -D -m 0755 $(@D)/fh8626-lens \
		$(TARGET_DIR)/usr/sbin/fh8626-lens
	cp -a $(ANJIA_AJL33PQ0866_BOARD_SUPPORT_PKGDIR)/files/. $(TARGET_DIR)/
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/etc/openipc
	printf '%s\n' '$(call qstrip,$(BR2_PACKAGE_ANJIA_AJL33PQ0866_TARGET_NAME))' \
		> $(TARGET_DIR)/etc/openipc/builder-target
	printf '%s\n' '$(call qstrip,$(BR2_PACKAGE_ANJIA_AJL33PQ0866_UPDATE_TARGET))' \
		> $(TARGET_DIR)/etc/openipc/update-target
endef

$(eval $(generic-package))
