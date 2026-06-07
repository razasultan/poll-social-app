<#
.SYNOPSIS
  Runs the Flutter app against the DEV Supabase backend (poll-social-app-dev).

.PARAMETER Release
  Run in release mode instead of the default debug mode.

.PARAMETER Device
  Flutter device id to target, e.g. "windows", "chrome" (passed through as -d).

.EXAMPLE
  .\scripts\run_dev.ps1
  .\scripts\run_dev.ps1 -Release -Device windows
#>
param(
    [switch]$Release,
    [string]$Device
)

$SupabaseUrl = "https://uwomsxkvjqrvhdpnbkit.supabase.co"
$SupabaseAnonKey = "sb_publishable_LgwGHGciORtyBWVRajywqA_JYzCokcF"

$flutterArgs = @(
    "run",
    "--dart-define=APP_ENV=dev",
    "--dart-define=SUPABASE_URL=$SupabaseUrl",
    "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey"
)

if ($Release) { $flutterArgs += "--release" }
if ($Device) { $flutterArgs += @("-d", $Device) }

& flutter @flutterArgs
