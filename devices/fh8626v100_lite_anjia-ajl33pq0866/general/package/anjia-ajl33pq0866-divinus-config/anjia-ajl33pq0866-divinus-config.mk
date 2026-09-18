################################################################################
#
# anjia-ajl33pq0866-divinus-config
#
################################################################################

ANJIA_AJL33PQ0866_DIVINUS_CONFIG_SITE_METHOD = local
ANJIA_AJL33PQ0866_DIVINUS_CONFIG_SITE = $(ANJIA_AJL33PQ0866_DIVINUS_CONFIG_PKGDIR)/files

define ANJIA_AJL33PQ0866_DIVINUS_CONFIG_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/divinus.yaml $(TARGET_DIR)/etc/divinus.yaml
endef

$(eval $(generic-package))
