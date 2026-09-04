<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Thermal Profile Developer Guide

AR: Expalin the parameters in the XML file.

Complete inventory of every system read and write performed by
[set_thermal_profile.sh](../../../tools/power-tuning/set_thermal_profile.sh), with the purpose of each
access, why it is done that way, what it affects on the platform, and what it
depends on.

Companion document:
[power-profile-developer-guide.md](power-profile-developer-guide.md) — the two
tools are complementary (power caps the watts, thermal caps the degrees) but
their I/O profiles are very different, as [§4](#4-thermal-sysfs-writes--none-by-design)
explains.

Legend used in the tables:

- **R** = read only, **W** = write, **RMW** = read-modify-write.
- "Fallback" = what the script does when the access fails. Unlike
  `set_power_profile.sh`, this script is **fail-closed**: most failures call
  `die` and abort rather than degrading.

---

## 1. Summary of access surfaces

| # | Surface | Mode | Root needed | Persists across reboot | Section |
|---|---------|------|-------------|------------------------|---------|
| 1 | Own source file (`$0`) for `--help` | R | no | n/a | [§2](#2-process-inputs-and-configuration-constants) |
| 2 | `/sys/class/thermal/cooling_device*/type` | R | no | n/a | [§3](#3-thermal-sysfs-reads) |
| 3 | `/sys/class/thermal/thermal_zone4/temp` | R | no | n/a | [§3](#3-thermal-sysfs-reads) |
| 4 | Thermal/cooling sysfs **writes** | — | — | — | **none** — see [§4](#4-thermal-sysfs-writes--none-by-design) |
| 5 | MSRs / RAPL / powercap | — | — | — | **none** — this script never touches them |
| 6 | Temp files + `thermald --test-mode` validation | R / W | yes | no | [§5](#5-temporary-files-and-the-validation-subprocess) |
| 7 | `/etc/thermald/thermal-conf.xml` (+ `.bak`) | R / W | yes | **yes** (on-disk) | [§6](#6-configuration-file-writes) |
| 8 | `/etc/systemd/system/thermald.service.d/override.conf` (+ `.bak`) | R / W | yes | **yes** (on-disk) | [§7](#7-systemd-override-writes) |
| 9 | `thermald.service` state (stop/start/restart/disable) | R / W | yes | **yes** for `--disable` (unit enablement) | [§8](#8-service-and-daemon-control) |
| 10 | Cooling-device `cur_state` (via the daemon) | W (indirect) | yes | no | [§9](#9-indirect-writes-performed-by-thermald) |

> **Mode contract.** The script has four mutually distinct execution modes, and
> they differ sharply in what they touch:
>
> | Mode | Reads | Writes | Root | Notes |
> |------|-------|--------|------|-------|
> | `--dry-run` | §2, §3 (cooling devices) | nothing | no | Prints the plan and summary; the generated XML is built in memory but only the summary is printed |
> | `-o FILE` | §2, §3 | **only** `FILE` | no | No validation, no daemon changes, no root gate — the write happens *before* the root check |
> | default (apply) | all | §5, §6, §7, §8 | **yes** | Validate → back up → install → override → restart → verify |
> | `--disable` | `systemctl is-active` | `systemctl stop` + `disable` | **yes** | Ignores all profile options; leaves config and override files in place |
>
> `--dry-run` composes with `--disable` (`--disable --dry-run` prints the two
> `systemctl` commands it would run and needs no root). It also takes precedence
> over `-o`: with both flags, the summary is printed and **no file is written**,
> because the dry-run branch at
> [set_thermal_profile.sh:265](../../../tools/power-tuning/set_thermal_profile.sh#L265) exits before the
> output-only branch at [282](../../../tools/power-tuning/set_thermal_profile.sh#L282).
>
> **Documentation drift:** the script's own `--help` text claims `--dry-run`
> "Emits the generated XML to stdout"
> ([set_thermal_profile.sh:38](../../../tools/power-tuning/set_thermal_profile.sh#L38)), but the
> implementation prints only the summary block — `$XML_CONTENT` is generated into
> a variable and never echoed. Use `-o /dev/stdout` (or `-o FILE`) to actually
> see the XML.

---

## 2. Process inputs and configuration constants

Unlike [set_power_profile.sh](../../../tools/power-tuning/set_power_profile.sh), this script reads **no
environment variables** — every path is a hardcoded constant. There is no
equivalent of `LPMD_CONF_DIR`/`LPMD_CONTROL`, so relocating `thermald` or its
config requires editing the script.

| Item | Mode | Purpose | Reason | Impact if changed |
|------|------|---------|--------|-------------------|
| `$0` (own source, lines `2`–`set -euo`) | R | `usage()` extracts the help text from the script's own header comment via `sed` | Single source of truth — the header block *is* the man page, so help can never drift from the documented options | Renaming/moving the script is fine, but reformatting the header comment (or moving `set -euo pipefail`) silently truncates or corrupts `--help` output |
| `EUID` | R | Root gate for the apply path and for `--disable` | Config install, systemd override and service restart all require root; `--dry-run` and `-o` do not | Non-root apply → `die` with an explicit "re-run with sudo (or use --dry-run / -o)" message. **No `sudo` self-re-exec** here, unlike `set_power_profile.sh` |
| `$@` (arguments) | R | Profile selection and trip-point overrides | — | Unknown argument → `die`. An invalid `--profile` value is rejected against the `cool\|warm\|hot\|thermal-max\|custom` allow-list. A bare positional word is **not** accepted as a profile |
| `THERMALD_BIN` = `/usr/sbin/thermald` | const | Binary used for the validation run and named in `ExecStart` | Must be an absolute path because systemd `ExecStart` requires one | Missing/not executable → `die` before any file is written |
| `CONF_FILE` = `/etc/thermald/thermal-conf.xml` | const | Install target for the generated profile | The path `thermald` reads by default | — |
| `OVERRIDE_DIR` / `OVERRIDE_FILE` | const | `/etc/systemd/system/thermald.service.d/override.conf` | Drop-in overrides the packaged unit without editing it | — |
| `COOLING_GLOB` = `/sys/class/thermal/cooling_device*` | const | Device-discovery glob | Cooling-device indices are not stable, so discovery is by `type`, never by index | — |
| `PKG_SENSOR` = `x86_pkg_temp` | const | Sensor every trip point is bound to | The CPU package sensor is the fastest-responding, platform-independent thermal signal | Changing it to a sensor `thermald` doesn't expose makes validation fail (fail-closed) |
| `ZONE_NAME` = `CPU_Zone` | const | Zone name in the XML, **and** the string grepped from the validation log | Doubles as the success token proving the zone actually loaded | Must match in both places or validation always fails |
| `EXEC_START` | const | `thermald --systemd --dbus-enable --ignore-default-control` | `--adaptive` is **deliberately omitted**: on DPTF/GDDV platforms the firmware adaptive tables would override `thermal-conf.xml` | Adding `--adaptive` silently hands authority back to firmware — the trip points would be installed but not enforced |

---

## 3. Thermal sysfs reads

| Path | Mode | Purpose | Reason | Impact | Fallback |
|------|------|---------|--------|--------|----------|
| `/sys/class/thermal/cooling_device*/type` | R | Enumerate which cooling devices exist, counted per type into the `HAVE` map | Writing a trip point that references an absent device makes `thermald` reject the whole config; discovery is by `type` because device indices are not stable across boots | Sets `USE_FAN`, `USE_PROC`, `USE_CLAMP`, `USE_CHRG` — i.e. which of the three escalation steps get emitted at all | Unreadable `type` → that device ignored. No devices at all → warning, then `die` ("refusing to write an empty zone") if none of the three expected types are present |
| `compgen -G "$COOLING_GLOB"` | R | Test whether the glob matches anything before iterating | Avoids iterating the literal unexpanded glob string | Emits "is this the target host?" warning when the whole class is missing | Warning only; the `die` above catches the fatal case |
| `/sys/class/thermal/thermal_zone4/temp` | R | Report the current package temperature on the final "Done." line | Cheap closing sanity check that the platform is in a sane thermal state | **Cosmetic only** — never used in a decision | `2>/dev/null \|\| echo 0` → prints `0C`. See the fragility note below |
| `$THERMALD_BIN` (`-x` test) | R | Confirm `thermald` is installed and executable | Fail before mutating anything rather than after | Gates the entire apply path | `die` |

> **Fragility — hardcoded `thermal_zone4`.** The closing temperature read
> hardcodes zone index 4, but zone numbering is not stable across platforms or
> boots and zone 4 is not guaranteed to be the `x86_pkg_temp` zone the rest of
> the script targets. It can silently print another sensor's temperature, or
> `0C` if the zone doesn't exist. Everything *functional* keys off `type`
> matching, so this affects only the last line of output. A robust form would
> resolve the zone by matching `/sys/class/thermal/thermal_zone*/type` against
> `x86_pkg_temp`.

> **Not read:** the generated XML contains a comment pointing at
> `/sys/class/dmi/id/product_name`, but the script **never reads it** — it emits
> the wildcard `<ProductName>*</ProductName>` so the profile applies on any
> machine. Pinning to a specific DMI product name is a manual follow-up.

---

## 4. Thermal sysfs writes — none, by design

This script writes **no** sysfs, **no** MSRs and **no** cooling-device state. It
is purely a *configuration generator plus daemon supervisor*: it writes two
files and restarts one service, and `thermald` then performs all runtime
actuation ([§9](#9-indirect-writes-performed-by-thermald)).

That is the central difference from
[set_power_profile.sh](power-profile-developer-guide.md), and it inverts the
persistence model:

| | `set_power_profile.sh` | `set_thermal_profile.sh` |
|---|---|---|
| Runtime actuation | Direct — MSR `0x610`/`0x65C`, powercap sysfs | Delegated entirely to `thermald` |
| Needs `msr-tools` / `msr` module | Yes (degrades to sysfs without) | **No** |
| Enforcement after reboot | **Lost** (RAPL caps are runtime-only) | **Survives** — `thermald` re-reads the installed XML at boot |
| Config on disk | Also written (`intel_lpmd` XML) | The *only* thing written |
| Effect if the daemon is dead | Cap still enforced by the PCU | Nothing is enforced beyond kernel defaults |

---

## 5. Temporary files and the validation subprocess

The apply path validates the generated XML with a real `thermald` parse **before**
touching `/etc`, so a malformed profile can never be installed.

| Path / action | Mode | Purpose | Reason | Impact | Cleanup |
|---------------|------|---------|--------|--------|---------|
| `mktemp /tmp/thermal-conf.XXXXXX.xml` | W | Stage the generated XML for validation, then serve as the `install` source | The same bytes are validated and installed, so the two can't diverge | Staging only | `trap 'rm -f "$tmp_xml"' EXIT` — removed on every exit path |
| `mktemp /tmp/thermald-verify.XXXXXX.log` | W | Capture the validation run's stdout+stderr | Needs to be greppable for the success tokens | Diagnostic source for the abort message | `rm -f` on both the success and failure branches |
| `timeout 8 thermald --no-daemon --test-mode --loglevel=info --config-file <tmp>` | R (subprocess) | Parse-check the config without actuating anything | `--test-mode` means the daemon evaluates the config but does not drive cooling devices; `timeout 8` bounds a hang | Decides install-or-abort | Exit status deliberately ignored (`\|\| true`) — the verdict comes from the log contents, not the return code |
| `grep "$ZONE_NAME"` **and** `grep -i "Product Name matched"` on the log | R | Two-token success test: the zone loaded **and** the platform matched | A config can parse yet match no platform, in which case no trip point would ever fire — both must hold | On success, counts `temp/power` lines to report the trip-point count. On failure → filtered log excerpt, restore daemon, `die` | — |
| `grep -c 'temp/power'` | R | Count parsed trip points for the report | Confirms the expected number of steps loaded | Output only | — |

**Validation window.** A running `thermald` holds a lock file, so a
`--no-daemon` validation run would exit with "already running" instead of
parsing. The script therefore **stops the daemon first**, recording
`was_active=1`. During that window the host falls back to kernel default
thermal control (it is not unprotected, but it is not on the strict profile
either). `restore_daemon()` restarts it if the script aborts, so the host is
never left with the daemon down.

---

## 6. Configuration file writes

| Path / action | Mode | Line | Purpose | Reason | Impact | Reversibility |
|---------------|------|------|---------|--------|--------|---------------|
| `$OUTPUT_OVERRIDE` (from `-o FILE`) | W (**overwrite**) | [283](../../../tools/power-tuning/set_thermal_profile.sh#L283) | Write the generated XML to an arbitrary path and exit | Lets you inspect, diff or version the profile without touching the system | **No validation, no root gate, no backup** — this write precedes the root check at [289](../../../tools/power-tuning/set_thermal_profile.sh#L289), so any path the invoking user can write is overwritten silently | Caller's responsibility |
| `cp -f "$CONF_FILE" "$CONF_FILE.bak"` | W | [330](../../../tools/power-tuning/set_thermal_profile.sh#L330) | Back up the existing thermald config before replacing it | Gives a one-command restore path, quoted in the failure message at [377](../../../tools/power-tuning/set_thermal_profile.sh#L377) | Creates `/etc/thermald/thermal-conf.xml.bak` | **`cp -f` overwrites the backup on every run** — see the warning below |
| `mkdir -p "$(dirname "$CONF_FILE")"` | W | [333](../../../tools/power-tuning/set_thermal_profile.sh#L333) | Create `/etc/thermald` when no config exists yet | A source-built `thermald` may not ship the directory | Creates a root-owned directory | Left behind |
| `install -m 0644 "$tmp_xml" "$CONF_FILE"` | W (**overwrite**) | [335](../../../tools/power-tuning/set_thermal_profile.sh#L335) | Install the validated profile as the live thermald config | Atomic, mode-explicit install of the exact bytes that passed validation | **This is the persistent change.** `thermald` re-reads it at every boot, so the profile survives reboot | `cp /etc/thermald/thermal-conf.xml.bak /etc/thermald/thermal-conf.xml && systemctl restart thermald` |
| `cmp -s "$tmp_xml" "$CONF_FILE"` | R | [393](../../../tools/power-tuning/set_thermal_profile.sh#L393) | Confirm the installed file is byte-identical to the validated one | Re-parsing after the restart is impossible (the live daemon holds the lock), so on-disk equality is checked instead | Warning if they differ | — |

> **Sharp edge — backup is not one-time.** `cp -f` at
> [330](../../../tools/power-tuning/set_thermal_profile.sh#L330) replaces `.bak` on **every** apply run. The
> first run preserves your original vendor config; a second run overwrites that
> backup with the first run's generated profile, so the pristine original is
> gone. `set_power_profile.sh` avoids this with a `[[ -e "$f.orig" ]] ||` guard
> ([set_power_profile.sh:613](../../../tools/power-tuning/set_power_profile.sh#L613)). Copy the `.bak`
> somewhere safe after the first run, or restore from the `thermald` package.
>
> Related: when **no** config existed beforehand, no `.bak` is created — but the
> abort message at [377](../../../tools/power-tuning/set_thermal_profile.sh#L377) still recommends
> `cp ${CONF_FILE}.bak ${CONF_FILE}`, which will fail in that case. Recovery
> there is `rm /etc/thermald/thermal-conf.xml` instead.

---

## 7. systemd override writes

The drop-in makes the installed XML authoritative. Written idempotently: the
desired content is compared against what is on disk, and the file is only
rewritten when it differs.

| Path / action | Mode | Line | Purpose | Reason | Impact | Reversibility |
|---------------|------|------|---------|--------|--------|---------------|
| `mkdir -p "$OVERRIDE_DIR"` | W | [351](../../../tools/power-tuning/set_thermal_profile.sh#L351) | Create `/etc/systemd/system/thermald.service.d` | Drop-in directory may not exist | Root-owned directory | Left behind |
| Read `$OVERRIDE_FILE` and compare to `$desired_override` | R | [352-363](../../../tools/power-tuning/set_thermal_profile.sh#L352-L363) | Decide create / update / no-op | Avoids a needless `daemon-reload` and needless `.bak` churn when the override is already correct | Sets `need_reload`; prints "Override already correct" on the no-op path | — |
| Write `$OVERRIDE_FILE` (create case) | W | [353](../../../tools/power-tuning/set_thermal_profile.sh#L353) | Install `ExecStart=` reset + re-declaration | The empty `ExecStart=` is required to clear the packaged unit's value before re-declaring it — without the reset, systemd would try to run **both** | Makes `--ignore-default-control` active and keeps `--adaptive` off, so `thermal-conf.xml` beats firmware DPTF/GDDV tables | `rm` the file + `systemctl daemon-reload` + restart |
| `cp -f "$OVERRIDE_FILE" "$OVERRIDE_FILE.bak"` then write (update case) | W | [357-358](../../../tools/power-tuning/set_thermal_profile.sh#L357-L358) | Preserve a differing pre-existing override before replacing it | The existing override may be someone else's deliberate tuning | Creates `override.conf.bak` | Same `cp -f` overwrite caveat as [§6](#6-configuration-file-writes) |

Override content written:

```ini
[Service]
# Managed by set_thermal_profile.sh
# Reset the packaged ExecStart, then re-declare it with --ignore-default-control
# and WITHOUT --adaptive, so the trip points in /etc/thermald/thermal-conf.xml
# are the sole thermal authority (firmware DPTF/GDDV adaptive tables would
# otherwise win).
ExecStart=
ExecStart=/usr/sbin/thermald --systemd --dbus-enable --ignore-default-control
```

---

## 8. Service and daemon control

| Action | Mode | Line | Purpose | Reason | Impact | Failure handling |
|--------|------|------|---------|--------|--------|------------------|
| `systemctl is-active --quiet thermald` | R | [301](../../../tools/power-tuning/set_thermal_profile.sh#L301) | Record `was_active` before the validation stop | Needed to decide whether `restore_daemon` should bring it back on abort | Drives the abort-path restore | — |
| `systemctl stop thermald` | W | [304](../../../tools/power-tuning/set_thermal_profile.sh#L304) | Release the lock file so the `--no-daemon` validation run can parse | A running daemon makes validation exit "already running" instead of parsing | Host reverts to kernel default thermal control for the validation window | Not guarded — a failure here aborts under `set -e` |
| `systemctl start thermald` (`restore_daemon`) | W | [308](../../../tools/power-tuning/set_thermal_profile.sh#L308) | Restart the daemon if the script aborts after stopping it | The host must never be left with the daemon down | Restores the *previous* config (the new one was not installed) | `2>/dev/null \|\| true` |
| `systemctl daemon-reload` | W | [367](../../../tools/power-tuning/set_thermal_profile.sh#L367) | Make systemd pick up a new/changed drop-in | A changed unit is otherwise ignored until reload | Re-reads all unit files | Only when `need_reload=1`; unguarded |
| `systemctl restart thermald` | W | [370](../../../tools/power-tuning/set_thermal_profile.sh#L370) | Start the daemon on the new config and new `ExecStart` | Config and flags are read at startup only | **This is the moment the profile becomes live.** `sleep 2` follows to let it settle | Unguarded — a hard failure aborts |
| `systemctl is-active --quiet thermald` (post-restart) | R | [374](../../../tools/power-tuning/set_thermal_profile.sh#L374) | Confirm the daemon actually came up | A restart can succeed and the daemon still exit | On failure: dumps `systemctl status -n 15` and `die`s with the restore command | Explicit |
| `systemctl status thermald --no-pager -n 15` | R | [376](../../../tools/power-tuning/set_thermal_profile.sh#L376) | Diagnostics for the failure path | Puts the reason in front of the user immediately | stderr only | `\|\| true` |
| `systemctl show thermald -p ExecStart` | R | [380](../../../tools/power-tuning/set_thermal_profile.sh#L380) | Extract the **effective** argv the daemon is running with | The drop-in could be shadowed or malformed; this reads what systemd actually resolved | Verifies `--ignore-default-control` present **and** `--adaptive` absent; warning if not | Empty value tolerated |
| `systemctl stop thermald` (`--disable`) | W | [114](../../../tools/power-tuning/set_thermal_profile.sh#L114) | Stop the daemon | User asked to revert to kernel default control | Strict trip points stop being enforced | `2>/dev/null \|\| true` |
| `systemctl disable thermald` (`--disable`) | W | [116](../../../tools/power-tuning/set_thermal_profile.sh#L116) | Prevent it starting at boot | Makes the revert persistent | **Persistent** unit-enablement change | `2>/dev/null \|\| true` |
| `systemctl is-active --quiet thermald` (`--disable`) | R | [117](../../../tools/power-tuning/set_thermal_profile.sh#L117) | Confirm it actually stopped | Something else may have restarted it | Warning if still active | Explicit |

> `--disable` leaves `thermal-conf.xml` and `override.conf` **in place**, so
> `sudo systemctl enable --now thermald` restores the exact strict profile
> without re-running this script.

---

## 9. Indirect writes performed by `thermald`

The script itself never actuates cooling. These are what the daemon does once the
config is live — the actual user-visible effect.

| Written by the daemon | Trip / source | Purpose | Impact |
|-----------------------|---------------|---------|--------|
| `Fan` cooling device `cur_state` | STEP 1, **active** at `FAN_C` (influence 100, sampling 5) | Spin fans up early | Removes heat with **no performance cost** — the whole point of tripping it first |
| `Processor` cooling device `cur_state` | STEP 2, **passive** at `PROC_C` (influence 150, sampling 2) | Cap CPU frequency | First actual performance reduction; proportional and relatively gentle |
| `intel_powerclamp` cooling device `cur_state` | STEP 3, **passive** at `CLAMP_C` (influence 200, sampling 1) | Inject forced idle cycles | Hard backstop; noticeably reduces throughput. Highest influence = strongest authority |
| `CHRG` cooling device `cur_state` | STEP 3 co-device, only with `--charge` and only if present (influence 50, sampling 5) | Throttle battery charging | Removes charging heat from the platform budget; the low influence marks it as a minor contributor |

The escalation ordering `FAN_C < PROC_C < CLAMP_C` is enforced by the script
([set_thermal_profile.sh:153-154](../../../tools/power-tuning/set_thermal_profile.sh#L153-L154)) — it is what
makes the sequence "cheap remedy first, expensive remedy last" rather than an
arbitrary set of thresholds. `<ControlType>SEQUENTIAL</ControlType>` on each trip
tells `thermald` to escalate through the listed devices in order rather than
engaging them all at once.

---

## 10. Generated XML structure

Emitted by `gen_xml()` / `gen_trip()`
([set_thermal_profile.sh:194-258](../../../tools/power-tuning/set_thermal_profile.sh#L194-L258)). Steps are
emitted **conditionally** — a step whose cooling device is absent is silently
omitted (with a warning), and if all three are absent the script refuses to
write an empty zone.

| Element | Value | Purpose |
|---------|-------|---------|
| `<Name>` | `Strict <CLAMP_C>C (<PROFILE>)` | Human-readable identification in thermald logs |
| `<ProductName>` | `*` | Wildcard — applies on any machine (see the note in [§3](#3-thermal-sysfs-reads)) |
| `<Preference>` | `QUIET` | Bias the daemon toward acoustics over performance |
| `<ThermalSensor><Type>` | `x86_pkg_temp` | The single sensor all trips bind to |
| `<AsyncCapable>` | `1` | Sensor supports interrupt-driven notification, so the daemon need not poll |
| `<ThermalZone><Type>` | `CPU_Zone` | Zone name, doubling as the validation success token |
| `<Temperature>` | trip °C **× 1000** | thermald expects millidegrees |
| `<type>` | `active` (STEP 1) / `passive` (STEPS 2, 3) | `active` = fans; `passive` = reduce heat generation |
| `<ControlType>` | `SEQUENTIAL` | Escalate through co-devices in listed order |
| `<influence>` | 100 / 150 / 200 (CHRG 50) | Relative authority — ascending, so the hard limit dominates |
| `<SamplingPeriod>` | 5 / 2 / 1 (CHRG 5) | Decreasing = react faster as the situation gets more serious |

---

## 11. External tool and kernel dependencies

| Dependency | Required for | Consequence if missing |
|------------|--------------|------------------------|
| `thermald` at `/usr/sbin/thermald` | Validation run, the whole apply path | `die` before anything is written |
| `thermald` support for `--test-mode`, `--no-daemon`, `--config-file`, `--ignore-default-control` | Validation and the override | Validation fails → fail-closed abort; missing `--ignore-default-control` would leave kernel/firmware control in play |
| `systemd` (`systemctl`) | [§8](#8-service-and-daemon-control) entirely | Apply path cannot proceed (unguarded calls abort under `set -e`) |
| `/sys/class/thermal` cooling devices (`Fan`, `Processor`, `intel_powerclamp`) | Step emission in [§10](#10-generated-xml-structure) | Each absent device drops its step with a warning; **all three** absent → `die` |
| `x86_pkg_temp` sensor exposed to thermald | Every trip point | Validation fails (fail-closed) |
| `CHRG` cooling device | `--charge` only | Warning, flag ignored, everything else proceeds |
| `intel_powerclamp` kernel module | STEP 3 | Hard backstop omitted; escalation tops out at frequency capping |
| `bash` ≥ 4 (associative arrays), `coreutils`, `sed`, `grep`, `cmp`, `mktemp`, `install`, `timeout` | Discovery map, help extraction, validation, install | Hard failure under `set -euo pipefail` |
| `sudo` / root | Apply path and `--disable` | `die` with guidance. **No self-re-exec** — you must invoke with `sudo` yourself |
| Non-DPTF platform, **or** the override in place | Trip points actually being honoured | On DPTF/GDDV platforms without `--ignore-default-control` (or with `--adaptive`), firmware adaptive tables win and the installed profile is inert |

No `msr-tools`, no `msr` module, no powercap driver — this script needs none of
them, unlike [set_power_profile.sh](power-profile-developer-guide.md#11-external-tool-and-kernel-dependencies).

Per the repository's sudo policy, probe with `sudo -n true` before invoking this
script under `sudo`; if it fails, run `sudo -v` in your own terminal first — see
[AGENTS.md](../../../AGENTS.md#sudo-handling-must-follow-for-all-skills-that-invoke-sudo).

---

## 12. Persistence and restore

| What was changed | Persists across reboot | How to restore |
|------------------|------------------------|----------------|
| `/etc/thermald/thermal-conf.xml` | **Yes** — thermald re-reads it at boot | `cp /etc/thermald/thermal-conf.xml.bak /etc/thermald/thermal-conf.xml && systemctl restart thermald` (or `rm` it if there was no prior config) |
| `/etc/thermald/thermal-conf.xml.bak` | Yes | Overwritten on every apply run — see the [§6](#6-configuration-file-writes) warning |
| `/etc/systemd/system/thermald.service.d/override.conf` | **Yes** | `rm` it (or restore `.bak`), then `systemctl daemon-reload && systemctl restart thermald` |
| `thermald` running state | Yes (unit stays enabled) | `systemctl restart thermald` |
| `thermald` **enablement** (after `--disable`) | **Yes** | `sudo systemctl enable --now thermald` — the config and override are still in place, so the strict profile returns as-is |
| Cooling-device `cur_state` (set by the daemon) | No | Follows automatically from the daemon's state |
| `/etc/thermald/` directory, `OVERRIDE_DIR` | Yes | Remove manually if desired |

---

## 13. Failure and abort paths

The script is deliberately fail-closed; these are the ways it stops, in
execution order.

| Condition | Stage | Behaviour | System left in |
|-----------|-------|-----------|----------------|
| Unknown argument / invalid `--profile` | Parse | `die` | Untouched |
| `custom` without all of `--fan`/`--proc`/`--clamp` | Resolve | `die` | Untouched |
| Non-integer trip point | Validate | `die` | Untouched |
| Ordering violated (`FAN ≥ PROC` or `PROC ≥ CLAMP`) | Validate | `die` | Untouched |
| `CLAMP_C ≥ 105` (too close to ~110 °C Tjmax) | Validate | `die` | Untouched |
| `FAN_C < 30` | Validate | **warn only** — "CPU may stay throttled" | Proceeds |
| One or two expected cooling devices absent | Discovery | **warn only**, step omitted | Proceeds with a shorter escalation |
| All three cooling devices absent | Discovery | `die` — "refusing to write an empty zone" | Untouched |
| `--charge` with no `CHRG` device | Discovery | **warn only**, flag ignored | Proceeds |
| Non-root on the apply path | Root gate | `die` (no self-re-exec) | Untouched |
| `thermald` binary missing | Root gate | `die` | Untouched |
| thermald rejects the generated XML | Validation | Filtered log excerpt → `restore_daemon` → `die` | **Untouched config**; daemon restarted on the old config |
| Installed file ≠ validated file | Post-restart | **warn only** | New config live |
| `thermald` not active after restart | Post-restart | `systemctl status` dump → `die` with restore command | New config installed but daemon down — restore from `.bak` |
| Effective `ExecStart` lacks `--ignore-default-control`, or has `--adaptive` | Post-restart | **warn only** — "check override.conf" | Config live but possibly **not authoritative** |

The validation-log filter
([set_thermal_profile.sh:320](../../../tools/power-tuning/set_thermal_profile.sh#L320)) greps for
`error|invalid|fail|Zone|Trip|matched` and then *excludes* `powercap|RAPL|sysfs`
noise — those lines are expected on platforms where thermald probes RAPL and
finds nothing relevant, and they would otherwise bury the real parse error.

---

## 14. Worked example — `--profile warm` in logical sequence

```bash
sudo tools/power-tuning/set_thermal_profile.sh --profile warm
```

**Assumed platform** (Intel Core Ultra laptop/edge node):

| Assumption | Source | Value |
|------------|--------|-------|
| Cooling devices present | `/sys/class/thermal/cooling_device*/type` | `Fan` ×1, `Processor` ×8, `intel_powerclamp` ×1, `TCPU` ×1 |
| `CHRG` device | same | absent (and `--charge` not passed) |
| Package sensor | thermald's view | `x86_pkg_temp` available |
| `thermald` | `/usr/sbin/thermald` | installed, currently **active** |
| Pre-existing config | `/etc/thermald/thermal-conf.xml` | present (vendor default) |
| Pre-existing override | `override.conf` | absent |

### 14.1 Step-by-step sequence

| # | Step | Access (R/W) | Value / result |
|---|------|--------------|----------------|
| 1 | Parse CLI | — | `PROFILE=warm`, `WANT_CHARGE=0`, `DRY_RUN=0`, `DISABLE=0`, `OUTPUT_OVERRIDE=""` |
| 2 | Validate profile against allow-list | — | `warm` accepted |
| 3 | `--disable` branch | — | skipped (`DISABLE=0`) |
| 4 | Resolve trip points from the profile table | — | `def_fan=60`, `def_proc=75`, `def_clamp=85` → `FAN_C=60`, `PROC_C=75`, `CLAMP_C=85` |
| 5 | Integer validation | — | all three pass |
| 6 | Ordering checks | — | `60 < 75 < 85` ✔; `85 < 105` ✔; `60 ≥ 30` so no idle-temp warning |
| 7 | Enumerate cooling devices | **R** `/sys/class/thermal/cooling_device*/type` | `HAVE=([Fan]=1 [Processor]=8 [intel_powerclamp]=1 [TCPU]=1)` |
| 8 | Decide which steps to emit | — | `USE_FAN=1`, `USE_PROC=1`, `USE_CLAMP=1`, `USE_CHRG=0` — all three steps emitted, no warnings |
| 9 | Generate XML in memory | — | `Strict 85C (warm)` zone `CPU_Zone`; trips at `60000` / `75000` / `85000` millidegrees (see [§14.3](#143-generated-thermald-config)) |
| 10 | Root gate | **R** `EUID` | 0 → proceed (no self-re-exec) |
| 11 | thermald binary check | **R** `-x /usr/sbin/thermald` | present |
| 12 | Stage XML | **W** `mktemp /tmp/thermal-conf.XXXXXX.xml` | `trap` registered to remove it on exit |
| 13 | Stop the running daemon for a clean parse | **R** `is-active` → **W** `systemctl stop thermald` | `was_active=1`; kernel default control applies during the window |
| 14 | Validate the config | **W** `mktemp` verify log; **R** `timeout 8 thermald --no-daemon --test-mode --config-file <tmp>` | log contains `CPU_Zone` **and** `Product Name matched` → accepted |
| 15 | Count trip points | **R** `grep -c 'temp/power'` | `3` → "Validation OK: zone 'CPU_Zone' loaded, 3 trip point(s) parsed" |
| 16 | Back up the existing config | **W** `cp -f` → `thermal-conf.xml.bak` | vendor default preserved (**this run only** — a second run overwrites it) |
| 17 | Install the validated config | **W** `install -m 0644` → `/etc/thermald/thermal-conf.xml` | persistent; survives reboot |
| 18 | Check the override | **R** `override.conf` | absent → create branch |
| 19 | Create the drop-in | **W** `mkdir -p` + write `override.conf` | `ExecStart=` reset + re-declaration without `--adaptive`; `need_reload=1` |
| 20 | Reload systemd | **W** `systemctl daemon-reload` | new drop-in picked up |
| 21 | Restart the daemon | **W** `systemctl restart thermald` + `sleep 2` | **profile becomes live** |
| 22 | Confirm it came up | **R** `is-active --quiet` | active |
| 23 | Read the effective argv | **R** `systemctl show thermald -p ExecStart` | `/usr/sbin/thermald --systemd --dbus-enable --ignore-default-control` |
| 24 | Authority check | — | `--ignore-default-control` present, `--adaptive` absent → "sole thermal authority ✔" |
| 25 | On-disk equality check | **R** `cmp -s <tmp> /etc/thermald/thermal-conf.xml` | identical → "validated pre-restart" confirmation |
| 26 | Closing temperature | **R** `/sys/class/thermal/thermal_zone4/temp` | e.g. `47000` → `47C` (cosmetic; hardcoded zone index) |
| 27 | Cleanup | **W** `rm -f <tmp_xml>` via `trap` | temp files gone |

`warm` is the default profile and the middle of the range: fans engage at 60 °C
well before any performance is sacrificed, frequency capping starts at 75 °C, and
forced idle injection is held back until 85 °C — 25 °C of headroom below the
~110 °C Tjmax. Contrast `thermal-max` (95 / 100 / 104 °C), which deliberately
runs near Tjmax and only just clears the `CLAMP_C < 105` guard.

### 14.2 Trip-point summary for this example

| Step | Trip | thermald `<Temperature>` | Type | Cooling device | Influence | Sampling | Cost when engaged |
|------|------|--------------------------|------|----------------|-----------|----------|-------------------|
| 1 | 60 °C | `60000` | `active` | `Fan` | 100 | 5 | None (acoustic only) |
| 2 | 75 °C | `75000` | `passive` | `Processor` | 150 | 2 | Frequency capped |
| 3 | 85 °C | `85000` | `passive` | `intel_powerclamp` | 200 | 1 | Forced idle cycles injected |

### 14.3 Generated thermald config

The interesting subset of the XML installed at step 17 (full generator at
[set_thermal_profile.sh:194-258](../../../tools/power-tuning/set_thermal_profile.sh#L194-L258)):

```xml
<?xml version="1.0"?>
<ThermalConfiguration>
    <Platform>
        <Name>Strict 85C (warm)</Name>
        <ProductName>*</ProductName>
        <Preference>QUIET</Preference>

        <ThermalSensors>
            <ThermalSensor>
                <Type>x86_pkg_temp</Type>
                <AsyncCapable>1</AsyncCapable>
            </ThermalSensor>
        </ThermalSensors>

        <ThermalZones>
            <ThermalZone>
                <Type>CPU_Zone</Type>
                <TripPoints>

                    <!-- STEP 1: fans on early (60C), no performance cost -->
                    <TripPoint>
                        <SensorType>x86_pkg_temp</SensorType>
                        <Temperature>60000</Temperature>
                        <type>active</type>
                        <ControlType>SEQUENTIAL</ControlType>
                        <CoolingDevice>
                            <type>Fan</type>
                            <influence>100</influence>
                            <SamplingPeriod>5</SamplingPeriod>
                        </CoolingDevice>
                    </TripPoint>

                    <!-- STEP 2: cap CPU frequency (75C) -->
                    <TripPoint>
                        <SensorType>x86_pkg_temp</SensorType>
                        <Temperature>75000</Temperature>
                        <type>passive</type>
                        <ControlType>SEQUENTIAL</ControlType>
                        <CoolingDevice>
                            <type>Processor</type>
                            <influence>150</influence>
                            <SamplingPeriod>2</SamplingPeriod>
                        </CoolingDevice>
                    </TripPoint>

                    <!-- STEP 3: hard limit (85C), inject idle cycles -->
                    <TripPoint>
                        <SensorType>x86_pkg_temp</SensorType>
                        <Temperature>85000</Temperature>
                        <type>passive</type>
                        <ControlType>SEQUENTIAL</ControlType>
                        <CoolingDevice>
                            <type>intel_powerclamp</type>
                            <influence>200</influence>
                            <SamplingPeriod>1</SamplingPeriod>
                        </CoolingDevice>
                    </TripPoint>

                </TripPoints>
            </ThermalZone>
        </ThermalZones>
    </Platform>
</ThermalConfiguration>
```

### 14.4 Console output

```text
[*] Cooling devices detected on this platform:
      Fan                x1
      Processor          x8
      TCPU               x1
      intel_powerclamp   x1
[*] Profile 'warm' -> Fan:60C  Processor:75C  powerclamp:85C
[*] Stopping running thermald for a clean validation...
[*] Validating generated config with thermald (test mode)...
[*] Validation OK: zone 'CPU_Zone' loaded, 3 trip point(s) parsed, platform matched.
[*] Backed up existing config -> /etc/thermald/thermal-conf.xml.bak
[*] Installed config -> /etc/thermald/thermal-conf.xml
[*] Created override -> /etc/systemd/system/thermald.service.d/override.conf
[*] systemd daemon-reloaded.
[*] thermald is active.
[*] Effective ExecStart: /usr/sbin/thermald --systemd --dbus-enable --ignore-default-control
[*] Daemon is the sole thermal authority (ignore-default-control set, adaptive off). ✔
[*] Live config: zone 'CPU_Zone' installed with trips 60/75/85C (validated pre-restart).

[*] Done. Current package temp: 47C
```

`[*]` lines are green `info`, `[!]` would be yellow `warn` (stderr), `[x]` red
`err` (stderr).

### 14.5 Preview without touching the platform

```console
$ tools/power-tuning/set_thermal_profile.sh --profile warm --dry-run
```

Runs steps 1-9 only — cooling-device discovery still happens (it is not gated on
`DRY_RUN`), so the reported step availability is accurate for the current host,
but nothing is written, no service is touched, and root is not required:

```text
[!] DRY-RUN: no files written, no services touched.
--- summary ---
    Profile:         warm
    Fan trip:        60C (active)
    Processor trip:  75C (passive)
    powerclamp trip: 85C (passive)
    CHRG device:     no
    Config target:   /etc/thermald/thermal-conf.xml
    Override:        /etc/systemd/system/thermald.service.d/override.conf
    ExecStart:       /usr/sbin/thermald --systemd --dbus-enable --ignore-default-control
--- would then: write config; ensure override; daemon-reload; restart thermald; verify parse ---
```

To capture the XML itself instead, use `-o`:

```console
$ tools/power-tuning/set_thermal_profile.sh --profile warm -o /tmp/warm.xml
```

This writes only that file — no validation, no daemon changes, and note that the
write happens **before** the root gate, so it succeeds as an unprivileged user
and will overwrite an existing target without warning.
