<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# Thermal Profile Developer Guide

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

> **Note:** For acronym definitions and additional context, refer to the scripts, user guide and skills documentation.

---

## 1. Summary of access surfaces
`set_thermal_profile.sh` generates a thermald configuration, validates it, installs it, and makes `thermald` the sole thermal authority for the package sensor. The script therefore touches a much narrower set of system interfaces than the power-profile tool, and it is intentionally fail-closed if a profile cannot be validated.

`set_thermal_profile.sh` operates through the following interfaces:

1. **Cooling-device discovery** via `/sys/class/thermal/cooling_device*/type`
   - Detects whether `Fan`, `Processor`, `intel_powerclamp`, and optional `CHRG` devices exist on the platform
   - Uses this to decide which thermald trip points to emit and which steps to omit
   - This is the primary gating input for the generated XML

2. **Current RAPL cap read** via `/sys/class/powercap/intel-rapl/intel-rapl:0/constraint_0_power_limit_uw`
   - Reads the currently active PL1 cap (when available) and embeds it in the generated thermald `<PPCC>` block
   - This keeps thermald from resetting to the platform default ACPI/DPTF cap during startup
   - If the file is unreadable or empty, the script emits a warning and skips the PPCC block

3. **Package temperature sanity read** via `/sys/class/thermal/thermal_zone4/temp`
   - Used only as a cosmetic final status check in the success output
   - It is not used to decide whether the profile is valid or whether thermald is allowed to apply it
   - The script treats it as informational only and falls back to `0C` if the zone is unavailable

4. **Generated thermald configuration** at `/etc/thermald/thermal-conf.xml`
   - Produces a strict staged profile on the `x86_pkg_temp` sensor named `CPU_Zone`
   - Emits `Fan`/`Processor`/`intel_powerclamp` steps in order, with `ControlType>SEQUENTIAL</ControlType>`
   - Optional `<PPCC>` block is embedded only when a current RAPL PL1 cap was read from sysfs

5. **Systemd override** at `/etc/systemd/system/thermald.service.d/override.conf`
   - Resets `ExecStart=` and re-declares `thermald --systemd --dbus-enable --ignore-default-control`
   - Deliberately omits `--adaptive` so the config file, not firmware adaptive tables, remains authoritative

6. **Service lifecycle** via `systemctl` (`stop`, `restart`, `daemon-reload`, `disable`)
   - Stops the daemon only long enough to validate the generated XML in `--no-daemon --test-mode`
   - Restarts it after installation so the new profile becomes live
   - `--disable` stops and disables `thermald`, leaving the config and override files in place but letting kernel default control take over

7. **Runtime behavior:** cooling actions are performed indirectly by `thermald`, not by the script itself. The XML is persistent on disk and re-read at boot, but the actual writes to cooling-device `cur_state` occur when the daemon is running.

The following table summarizes the access interfaces and their properties:

| # | Surface | Mode | Root needed | Persists across reboot |
|---|---------|------|-------------|------------------------|
| 1 | `/sys/class/thermal/cooling_device*/type` | R | no | n/a |
| 2 | `/sys/class/powercap/intel-rapl/intel-rapl:0/constraint_0_power_limit_uw` | R | no | n/a |
| 3 | `/sys/class/thermal/thermal_zone4/temp` | R | no | n/a |
| 4 | `/etc/thermald/thermal-conf.xml` (+ `.bak`) | R / W | yes | **yes** (on-disk) |
| 5 | `/etc/systemd/system/thermald.service.d/override.conf` (+ `.bak`) | R / W | yes | **yes** (on-disk) |
| 6 | `thermald.service` state (stop/start/restart/disable) | R / W | yes | **yes** for `--disable` (unit enablement) |
| 7 | Cooling-device `cur_state` (via the daemon) | W (indirect) | yes | no |

---

## 3. Thermal sysfs reads

| Path | Purpose | Fallback |
|------|---------|----------|
| `/sys/class/thermal/cooling_device*/type` | Enumerate which cooling devices exist, counted per type into the `HAVE` map. This decides which of the `Fan`, `Processor`, `intel_powerclamp`, and optional `CHRG` steps are emitted. | Unreadable `type` → that device ignored. No devices at all → warning, then `die` ("refusing to write an empty zone") if none of the three expected types are present. |
| `compgen -G "$COOLING_GLOB"` | Detect the available cooling devices (/sys/class/thermal/cooling_device*) on the platform. | Warning only; the `die` above catches the fatal case. |
| `/sys/class/thermal/thermal_zone4/temp` | Reporting the current package temperature. |  thermal-zone index 4 is not stable across machines or boots, so the value can be for the wrong sensor or show `0C` |
| `thermald` executable | Confirm `thermald` is installed and executable before mutating anything. | `die` |

> **Not used:** the generated XML includes a comment about
> `/sys/class/dmi/id/product_name`, but the script does not read that file.
> Instead, it writes `<ProductName>*</ProductName>`, which lets the profile apply
> to any machine. Restricting the profile to a specific machine would require a
> manual change.

---

## 4. Thermal sysfs writes — none, by design

The `set_thermal_profile.sh` script writes **no** sysfs, **no** MSRs and **no** cooling-device state. It
is purely a *configuration generator plus daemon supervisor*: it writes two
files and restarts one service, and `thermald` then performs all runtime
actuation.

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

| Path / action | Mode | Purpose | Reason |
|---------------|------|---------|--------|
| `mktemp /tmp/thermal-conf.XXXXXX.xml` | W | Stage the generated XML for validation, then serve as the `install` source | The same bytes are validated and installed, so the two can't diverge |
| `mktemp /tmp/thermald-verify.XXXXXX.log` | W | Capture the validation run's stdout+stderr | Needs to be greppable for the success tokens |
| `timeout 8 thermald --no-daemon --test-mode --loglevel=info --config-file <tmp>` | R (subprocess) | Parse-check the config without actuating anything | `--test-mode` means the daemon evaluates the config but does not drive cooling devices; `timeout 8` bounds a hang |
| `grep "$ZONE_NAME"` **and** `grep -i "Product Name matched"` on the log | R | Two-token success test: the zone loaded **and** the platform matched | A config can parse yet match no platform, in which case no trip point would ever fire — both must hold |

**Validation window.** A running `thermald` holds a lock file, so a
`--no-daemon` validation run would exit with "already running" instead of
parsing. The script therefore **stops the daemon first**, recording
`was_active=1`. During that window the host falls back to kernel default
thermal control (it is not unprotected, but it is not on the strict profile
either). `restore_daemon()` restarts it when XML validation fails after the
daemon was stopped. Failures after validation can leave the daemon stopped and
require manual recovery.

---

## 6. Configuration file writes

| Path / action | Mode | Purpose | Reason |
|---------------|------|---------|--------|
| `$OUTPUT_OVERRIDE` (from `-o FILE`) | W (**overwrite**) | Write the generated XML to an arbitrary path and exit | Lets you inspect, diff or version the profile without touching the system |
| `cp -f "$CONF_FILE" "$CONF_FILE.bak"` | W | Back up the existing thermald config before replacing it | Gives a one-command restore path, quoted in the failure message |
| `mkdir -p "$(dirname "$CONF_FILE")"` | W | Create `/etc/thermald` when no config exists yet | A source-built `thermald` may not ship the directory |
| `install -m 0644 "$tmp_xml" "$CONF_FILE"` | W (**overwrite**) | Install the validated profile as the live thermald config | Atomic, mode-explicit install of the exact bytes that passed validation |
| `cmp -s "$tmp_xml" "$CONF_FILE"` | R | Confirm the installed file is byte-identical to the validated one | Re-parsing after the restart is impossible (the live daemon holds the lock), so on-disk equality is checked instead |

> **Sharp edge — backup is not one-time.** The `.bak` is overwritten on **every** apply run. The
> first run preserves your original vendor config; a second run overwrites that
> backup with the first run's generated profile, so the pristine original is
> gone. Copy the `.bak`somewhere safe after the first run, or restore from the `thermald` package if requird to
> restore to original file.

---

## 7. systemd override writes

The drop-in makes the installed XML authoritative. Written idempotently: the
desired content is compared against what is on disk, and the file is only
rewritten when it differs.

| Path / action | Mode | Purpose | Reason |
|---------------|------|---------|--------|
| `mkdir -p "$OVERRIDE_DIR"` | W | Create `/etc/systemd/system/thermald.service.d` | Drop-in directory may not exist |
| Read `$OVERRIDE_FILE` and compare to `$desired_override` | R | Decide create / update / no-op | Avoids a needless `daemon-reload` and needless `.bak` churn when the override is already correct |
| Write `$OVERRIDE_FILE` (create case) | W | Install `ExecStart=` reset + re-declaration | The empty `ExecStart=` is required to clear the packaged unit's value before re-declaring it — without the reset, systemd would try to run **both** |
| `cp -f "$OVERRIDE_FILE" "$OVERRIDE_FILE.bak"` then write (update case) | W | Preserve a differing pre-existing override before replacing it | The existing override may be someone else's deliberate tuning |

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

The script temporarily stops `thermald` for validation, then reloads systemd, restarts the daemon with the new configuration, and verifies that it is active and authoritative.

The following table explains each service-control action, its access mode, and why the script performs it.

| Action | Mode | Purpose | Reason |
|--------|------|---------|--------|
| `systemctl is-active --quiet thermald` | R | Record `was_active` before the validation stop | Needed to decide whether `restore_daemon` should bring it back on abort |
| `systemctl stop thermald` | W | Release the lock file so the `--no-daemon` validation run can parse | A running daemon makes validation exit "already running" instead of parsing |
| `systemctl start thermald` (`restore_daemon`) | W | Restart the daemon if the script aborts after stopping it | The host must never be left with the daemon down |
| `systemctl daemon-reload` | W | Make systemd pick up a new/changed drop-in | A changed unit is otherwise ignored until reload |
| `systemctl restart thermald` | W | Start the daemon on the new config and new `ExecStart` | Config and flags are read at startup only |
| `systemctl is-active --quiet thermald` (post-restart) | R | Confirm the daemon actually came up | A restart can succeed and the daemon still exit |
| `systemctl status thermald --no-pager -n 15` | R | Diagnostics for the failure path | Puts the reason in front of the user immediately |
| `systemctl show thermald -p ExecStart` | R | Extract the **effective** argv the daemon is running with | The drop-in could be shadowed or malformed; this reads what systemd actually resolved |
| `systemctl stop thermald` (`--disable`) | W | Stop the daemon | User asked to revert to kernel default control |
| `systemctl disable thermald` (`--disable`) | W | Prevent it starting at boot | Makes the revert persistent |
| `systemctl is-active --quiet thermald` (`--disable`) | R | Confirm it actually stopped | Something else may have restarted it |

> `--disable` leaves `thermal-conf.xml` and `override.conf` **in place**, so
> `sudo systemctl enable --now thermald` restores the exact strict profile
> without re-running this script.

---

## 9. Indirect writes performed by `thermald`

The script itself never actuates cooling. These are what the daemon does once the
config is live — the actual user-visible effect.

| Written by the daemon | Trip / source | Purpose | Impact |
|-----------------------|---------------|---------|--------|
| `Fan` cooling device `cur_state` | STEP 1, **active** at `FAN_C` | Spin fans up early | Removes heat with **no performance cost** — the whole point of tripping it first |
| `Processor` cooling device `cur_state` | STEP 2, **passive** at `PROC_C` | Cap CPU frequency | First actual performance reduction; proportional and relatively gentle |
| `intel_powerclamp` cooling device `cur_state` | STEP 3, **passive** at `CLAMP_C` | Inject forced idle cycles | Hard backstop; noticeably reduces throughput. Highest influence = strongest authority |
| `CHRG` cooling device `cur_state` | STEP 3 co-device, only with `--charge` and only if present | Throttle battery charging | Removes charging heat from the platform budget; the low influence marks it as a minor contributor |

The escalation ordering `FAN_C < PROC_C < CLAMP_C` is enforced by the script, it is what
makes the sequence "cheap remedy first, expensive remedy last" rather than an
arbitrary set of thresholds. `<ControlType>SEQUENTIAL</ControlType>` on each trip
tells `thermald` to escalate through the listed devices in order rather than
engaging them all at once.

---

## 10. Generated XML structure

Emitted by `gen_xml()` / `gen_trip()` in the `set_thermal_profile.sh`. Steps are
emitted **conditionally** — a step whose cooling device is absent is silently
omitted (with a warning), and if all three are absent the script refuses to
write an empty zone.

| Element | Value | Purpose |
|---------|-------|---------|
| `<ThermalConfiguration>` | Root element | Contains the complete thermald configuration |
| `<Platform>` | Platform profile container | Groups the platform name, power policy, sensors, and thermal zones |
| `<Name>` | `Strict <CLAMP_C>C (<PROFILE>)` | Human-readable identification in thermald logs |
| `<ProductName>` | `*` | Wildcard — applies on any machine (see the note in [§3](#3-thermal-sysfs-reads)) |
| `<Preference>` | `QUIET` | Bias the daemon toward acoustics over performance |
| `<PPCC>` | Optional RAPL power-control block | Keeps thermald's startup RAPL reset aligned with the current package cap; omitted when the cap cannot be read |
| `<PowerLimitIndex>` | `0` | Selects the package RAPL power-limit control |
| `<PowerLimitMaximum>` | Current PL1 cap in mW | Upper bound for the PPCC power limit; `200000` = 200 W |
| `<PowerLimitMinimum>` | 30% of the current cap, minimum 2000 mW | Lower bound thermald may use for the PPCC power limit |
| `<TimeWindowMinimum>` / `<TimeWindowMaximum>` | `20` / `60` seconds | Allowed minimum and maximum PPCC time windows |
| `<StepSize>` | `1000` mW | PPCC power adjustment increment; 1 W |
| `<ThermalSensor><Type>` | `x86_pkg_temp` | The single sensor all trips bind to |
| `<AsyncCapable>` | `1` | Sensor supports interrupt-driven notification, so the daemon need not poll |
| `<ThermalZone><Type>` | `CPU_Zone` | Zone name, doubling as the validation success token |
| `<Temperature>` | trip °C **× 1000** | thermald expects millidegrees |
| `<type>` | `active` (STEP 1) / `passive` (STEPS 2, 3) | `active` = fans; `passive` = reduce heat generation |
| `<ControlType>` | `SEQUENTIAL` | Escalate through co-devices in listed order |
| `<influence>` | 100 / 150 / 200 (CHRG 50) | Relative authority — ascending, so the hard limit dominates |
| `<SamplingPeriod>` | 5 / 2 / 1 (CHRG 5) | Decreasing = react faster as the situation gets more serious |

---

## 12. Persistence and restore

| What was changed | Persists across reboot | How to restore |
|------------------|------------------------|----------------|
| `/etc/thermald/thermal-conf.xml` | **Yes** — thermald re-reads it at boot | If `.bak` exists: `sudo cp /etc/thermald/thermal-conf.xml.bak /etc/thermald/thermal-conf.xml && sudo systemctl restart thermald`; if no backup exists, remove the generated file and restore the distribution config before restarting |
| `/etc/thermald/thermal-conf.xml.bak` | Yes | Overwritten on every apply run |
| `/etc/systemd/system/thermald.service.d/override.conf` | **Yes** | Remove it, or restore `.bak` if the script created one, then run `sudo systemctl daemon-reload && sudo systemctl restart thermald` |
| `thermald` running state | Yes (unit stays enabled) | `sudo systemctl restart thermald` |
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
| thermald rejects the generated XML | Validation | Filtered log excerpt → `restore_daemon` → `die` | **Untouched config**; daemon is restarted on the old config when it was active before validation |
| Installed file ≠ validated file | Post-restart | **warn only** | New config live |
| `thermald` not active after restart | Post-restart | `systemctl status` dump → `die` with restore guidance | New config may be installed while the daemon is down; restore `.bak` only if it exists, then run `sudo systemctl restart thermald` |
| Effective `ExecStart` lacks `--ignore-default-control`, or has `--adaptive` | Post-restart | **warn only** — "check override.conf" | Config live but possibly **not authoritative** |
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
| 1 | Parse and validate the requested profile and trip-point ordering | — | CLI values parsed, `warm` accepted, `--disable` skipped, trip points resolved to `FAN_C=60`, `PROC_C=75`, `CLAMP_C=85`, all values pass integer validation, and `60 < 75 < 85`, `85 < 105`, and `60 ≥ 30` checks pass |
| 2 | Discover devices, generate the profile, and check prerequisites | **R** `/sys/class/thermal/cooling_device*/type`, `EUID`, `-x /usr/sbin/thermald` | `HAVE=([Fan]=1 [Processor]=8 [intel_powerclamp]=1 [TCPU]=1)`; all available steps are selected; XML is generated for `CPU_Zone`; root and `thermald` checks pass |
| 3 | Stage XML | **W** `mktemp /tmp/thermal-conf.XXXXXX.xml` | `trap` registered to remove it on exit |
| 4 | Stop the running daemon for a clean parse | **R** `is-active` → **W** `systemctl stop thermald` | `was_active=1`; kernel default control applies during the window |
| 5 | Validate, back up, and install the profile | **W** `mktemp` verify log, `cp -f` → `thermal-conf.xml.bak`, `install -m 0644` → `/etc/thermald/thermal-conf.xml`; **R** `timeout 8 thermald --no-daemon --test-mode --config-file <tmp>`, `grep -c 'temp/power'` | `CPU_Zone` and `Product Name matched` are present; `3` trip points are parsed; the vendor config is backed up and the validated XML is installed persistently |
| 6 | Check and install the systemd override | **R** `override.conf`; **W** `mkdir -p` + write `override.conf` | Existing content is compared; the drop-in is created or updated with an `ExecStart=` reset and re-declaration without `--adaptive`; `need_reload=1` when changed |
| 7 | Reload, restart, and verify the daemon | **W** `systemctl daemon-reload`, `systemctl restart thermald` + `sleep 2`; **R** `is-active --quiet` | systemd loads the drop-in, the profile becomes live, and `thermald` is active |
| 8 | Verify the live command, authority, and installed file | **R** `systemctl show thermald -p ExecStart`, `cmp -s <tmp> /etc/thermald/thermal-conf.xml` | Effective argv is `/usr/sbin/thermald --systemd --dbus-enable --ignore-default-control`; `--adaptive` is absent; the daemon is the sole thermal authority; installed XML matches the validated file |
| 9 | Report temperature and clean up | **R** `/sys/class/thermal/thermal_zone4/temp`; **W** `rm -f <tmp_xml>` via `trap` | e.g. `47000` → `47C` (cosmetic; hardcoded zone index); temporary files are removed |

`warm` is the default profile and the middle of the range: fans engage at 60 °C
well before any performance is sacrificed, frequency capping starts at 75 °C, and
forced idle injection is held back until 85 °C — 25 °C of headroom below the
~110 °C Tjmax. Contrast `thermal-max` (95 / 100 / 104 °C), which deliberately
runs near Tjmax and only just clears the `CLAMP_C < 105` guard.

### 14.2 Trip-point summary for this example

| Step | Trip | thermald `<Temperature>` | Type | Cooling device | Sampling(Sec) | Cost when engaged |
|------|------|--------------------------|------|----------------|----------|-------------------|
| 1 | 60 °C | `60000` | `active` | `Fan` | 5 | None (acoustic only) |
| 2 | 75 °C | `75000` | `passive` | `Processor` | 2 | Frequency capped |
| 3 | 85 °C | `85000` | `passive` | `intel_powerclamp` | 1 | Forced idle cycles injected |

### 14.3 Generated thermald config

The optional `<PPCC>` block preserves the currently applied RAPL package power
cap when `thermald` starts. Without it, thermald may reset its RAPL cooling
device to the platform ACPI/DPTF default instead of the cap selected by the
power-profile tool. The block is emitted only when
`constraint_0_power_limit_uw` can be read. PPCC power values are in mW and time
windows are in seconds; in the example below `25000` means 25 W and `7500`
means 7.5 W. `PowerLimitMinimum` is generated as 30% of the current cap, with a
minimum of 2000 mW, and `StepSize` is 1000 mW (1 W).

The following example shows a reference thermal configuration file generated by the script.

```xml
<?xml version="1.0"?>
<ThermalConfiguration>
    <Platform>
        <Name>Strict 85C (warm)</Name>
        <!-- Wildcard: applies on any machine. Replace * with the exact DMI
             product name (cat /sys/class/dmi/id/product_name) to pin it. -->
        <ProductName>*</ProductName>
        <Preference>QUIET</Preference>

        <!-- thermald always force-writes its RAPL cooling device to this PPCC
             limit at startup (see thd_cdev_rapl.cpp update()); giving it the cap
             already applied (e.g. by set_power_profile.sh) means that reset lands
             on our value, not the platform default. -->
        <PPCC>
            <PowerLimitIndex>0</PowerLimitIndex>
            <PowerLimitMaximum>25000</PowerLimitMaximum>
            <PowerLimitMinimum>7500</PowerLimitMinimum>
            <TimeWindowMinimum>20</TimeWindowMinimum>
            <TimeWindowMaximum>60</TimeWindowMaximum>
            <StepSize>1000</StepSize>
        </PPCC>

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
The following is the reference output generated by applying the `warm` profile.
```text
[*] Cooling devices detected on this platform:
      CHRG               x1
      Fan                x5
      Processor          x16
      TFN1               x1
      intel_powerclamp   x1
[*] Current RAPL PL1 cap: 25W (from /sys/class/powercap/intel-rapl/intel-rapl:0/constraint_0_power_limit_uw); embedding as PPCC max.
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

[*] Done. Current package temp: 29C

```

`[*]` lines are green `info`, `[!]` would be yellow `warn` (stderr), `[x]` red
`err` (stderr).

### 14.5 Preview without touching the platform

```console
$ tools/power-tuning/set_thermal_profile.sh --profile warm --dry-run
```

Cooling-device discovery still happens (it is not gated on
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
