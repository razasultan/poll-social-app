# Convenience targets for running the app against DEV or PROD Supabase
# without retyping the long `flutter run --dart-define=...` invocation.
#
# Usage:
#   make run-dev            # debug, default device
#   make run-dev-release
#   make run-prod
#   make run-prod-release
#
# Pass extra flutter args (e.g. a device id) via FLUTTER_ARGS:
#   make run-dev FLUTTER_ARGS="-d windows"

SUPABASE_DEV_URL := https://uwomsxkvjqrvhdpnbkit.supabase.co
SUPABASE_DEV_ANON_KEY := sb_publishable_LgwGHGciORtyBWVRajywqA_JYzCokcF

# PROD project (poll-social-app). Get a fresh publishable key from the
# Supabase dashboard (Settings -> API -> Publishable key) if it ever rotates.
SUPABASE_PROD_URL := https://ioweogjlumrzcbejwbeb.supabase.co
SUPABASE_PROD_ANON_KEY := sb_publishable_eBRj_ukaVQGpeAfcjwKvjQ_8sIu7PIP

DEV_DEFINES := --dart-define=APP_ENV=dev \
               --dart-define=SUPABASE_URL=$(SUPABASE_DEV_URL) \
               --dart-define=SUPABASE_ANON_KEY=$(SUPABASE_DEV_ANON_KEY)

PROD_DEFINES := --dart-define=APP_ENV=prod \
                --dart-define=SUPABASE_URL=$(SUPABASE_PROD_URL) \
                --dart-define=SUPABASE_ANON_KEY=$(SUPABASE_PROD_ANON_KEY)

.PHONY: run-dev run-dev-release run-prod run-prod-release

run-dev:
	flutter run $(DEV_DEFINES) $(FLUTTER_ARGS)

run-dev-release:
	flutter run --release $(DEV_DEFINES) $(FLUTTER_ARGS)

run-prod:
	flutter run $(PROD_DEFINES) $(FLUTTER_ARGS)

run-prod-release:
	flutter run --release $(PROD_DEFINES) $(FLUTTER_ARGS)
