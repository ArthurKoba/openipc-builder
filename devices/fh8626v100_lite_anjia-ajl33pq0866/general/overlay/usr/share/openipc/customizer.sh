#!/bin/sh
#
# ANJIA AJL33PQ0866 first-boot hook.
#
# Persistent environment policy is owned by the idempotent S32 service so it
# can repair a stale/missed first-boot write after an update. Running it here
# keeps ordinary OpenIPC customizer semantics without making correctness depend
# on /etc/custom.ok.
exec /etc/init.d/S32anjia-env start
