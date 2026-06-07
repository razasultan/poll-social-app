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

# Fill in the PROD anon key (Supabase dashboard -> poll-social-app -> Settings
# -> API -> Publishable key; also documented in Notion). The PROD project may
# need to be resumed first if it shows as paused/inactive.
SUPABASE_PROD_URL := https://ioweogjlumrzcbejwbeb.supabase.co
SUPABASE_PROD_ANON_KEY := YOUR_PROD_ANON_KEY

DEV_DEFINES := --dart-define=APP_ENV=dev \
               --dart-define=SUPABASE_URL=$(SUPABASE_DEV_URL) \
               --dart-define=SUPABASE_ANON_KEY=$(SUPABASE_DEV_ANON_KEY)

PROD_DEFINES := --dart-define=APP_ENV=prod \
                --dart-define=SUPABASE_URL=$(SUPABASE_PROD_URL) \
                --dart-define=SUPABASE_ANON_KEY=$(SUPABASE_PROD_ANON_KEY)

.PHONY: run-dev run-dev-release run-prod run-prod-release check-prod-key

run-dev:
	flutter run $(DEV_DEFINES) $(FLUTTER_ARGS)

run-dev-release:
	flutter run --release $(DEV_DEFINES) $(FLUTTER_ARGS)

run-prod: check-prod-key
	flutter run $(PROD_DEFINES) $(FLUTTER_ARGS)

run-prod-release: check-prod-key
	flutter run --release $(PROD_DEFINES) $(FLUTTER_ARGS)

check-prod-key:
	@if [ "$(SUPABASE_PROD_ANON_KEY)" = "YOUR_PROD_ANON_KEY" ]; then \
		echo "Set SUPABASE_PROD_ANON_KEY in the Makefile to the PROD project's publishable anon key before running this." >&2; \
		exit 1; \
	fi
