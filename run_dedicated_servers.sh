#!/bin/bash

set -euo pipefail

steamcmd_dir="${DST_STEAMCMD_DIR:-/root/steam/steamcmd}"
install_dir="${DST_INSTALL_DIR:-/root/steam/dst}"
cluster_name="${DST_CLUSTER_NAME:-Cluster_1}"
dontstarve_dir="${DST_DONTSTARVE_DIR:-/root/.klei/DoNotStarveTogether}"
defaults_dir="${DST_DEFAULTS_DIR:-/root/steam/defaults}"
mods_dir="${DST_MODS_DIR:-$install_dir/mods}"
log_dir="${DST_LOG_DIR:-$dontstarve_dir/logs}"
log_max_size="${DST_LOG_MAX_SIZE:-10M}"
log_rotate_count="${DST_LOG_ROTATE_COUNT:-3}"
log_rotate_interval="${DST_LOG_ROTATE_INTERVAL:-60}"
shutdown_timeout="${DST_SHUTDOWN_TIMEOUT:-60}"
auto_backup_enabled="${DST_AUTOBACKUP_ENABLED:-1}"
auto_backup_interval_days="${DST_AUTOBACKUP_INTERVAL_DAYS:-10}"
auto_backup_max_backups="${DST_AUTOBACKUP_MAX_BACKUPS:-10}"
auto_backup_nice="${DST_AUTOBACKUP_NICE:-10}"
auto_backup_announce_start="${DST_AUTOBACKUP_ANNOUNCE_START:-[DST] World backup started.}"
auto_backup_announce_end="${DST_AUTOBACKUP_ANNOUNCE_END:-[DST] World backup finished.}"

cluster_dir="$dontstarve_dir/$cluster_name"
default_cluster_dir="$defaults_dir/$cluster_name"
default_mods_dir="$defaults_dir/mods"
steamcmd_log="$log_dir/steamcmd.log"
master_log="$log_dir/master.log"
caves_log="$log_dir/caves.log"
auto_backup_dir="${DST_AUTOBACKUP_DIR:-$dontstarve_dir/autobackups/$cluster_name}"
auto_backup_name_prefix="Cluster_"
template_stamp="$cluster_dir/.dst-template-seeded"
master_console_pipe="/tmp/dst-master.console"
caves_console_pipe="/tmp/dst-caves.console"
logrotate_conf="/tmp/dst-logrotate.conf"
logrotate_state="/tmp/dst-logrotate.state"

function fail()
{
	echo "[dst] Error: $*" >&2
	exit 1
}

function info()
{
	echo "[dst] $*"
}

function check_for_file()
{
	if [ ! -e "$1" ]; then
		fail "Missing file: $1"
	fi
}

function check_for_directory()
{
	if [ ! -d "$1" ]; then
		fail "Missing directory: $1"
	fi
}

function cleanup_children()
{
	local pid

	for pid in "${master_pid:-}" "${caves_pid:-}" "${logrotate_pid:-}" "${auto_backup_pid:-}"; do
		if [ -n "$pid" ]; then
			kill "$pid" 2>/dev/null || true
		fi
	done

	for pid in "${master_pid:-}" "${caves_pid:-}" "${logrotate_pid:-}" "${auto_backup_pid:-}"; do
		if [ -n "$pid" ]; then
			wait "$pid" 2>/dev/null || true
		fi
	done

	close_console_input "${master_console_fd:-}" "$master_console_pipe"
	close_console_input "${caves_console_fd:-}" "$caves_console_pipe"
}

function generate_hex_id()
{
	local bytes="${1:-8}"

	od -An -N"$bytes" -tx1 /dev/urandom \
		| tr -d ' \n' \
		| tr '[:lower:]' '[:upper:]'
}

function is_enabled()
{
	case "${1:-}" in
		1|true|TRUE|yes|YES|on|ON)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

function is_non_negative_integer()
{
	[[ "${1:-}" =~ ^[0-9]+$ ]]
}

function validate_auto_backup_config()
{
	if ! is_non_negative_integer "$auto_backup_interval_days" || [ "$auto_backup_interval_days" -eq 0 ]; then
		fail "DST_AUTOBACKUP_INTERVAL_DAYS must be a positive integer."
	fi

	if ! is_non_negative_integer "$auto_backup_max_backups" || [ "$auto_backup_max_backups" -eq 0 ]; then
		fail "DST_AUTOBACKUP_MAX_BACKUPS must be a positive integer."
	fi
}

function create_console_input()
{
	local pipe="$1"
	local fd_var="$2"
	local fd

	rm -f "$pipe"
	mkfifo "$pipe"
	exec {fd}<>"$pipe"
	printf -v "$fd_var" '%s' "$fd"
}

function close_console_input()
{
	local fd="${1:-}"
	local pipe="$2"

	if [ -n "$fd" ]; then
		eval "exec ${fd}>&-" 2>/dev/null || true
		eval "exec ${fd}<&-" 2>/dev/null || true
	fi

	rm -f "$pipe"
}

function send_console_command()
{
	local fd="${1:-}"
	local command="$2"

	if [ -n "$fd" ]; then
		printf '%s\n' "$command" >&"$fd" 2>/dev/null || true
	fi
}

function escape_lua_string()
{
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

function announce_cluster_message()
{
	local message="$1"
	local escaped
	local command

	escaped="$(escape_lua_string "$message")"
	command="c_announce(\"$escaped\")"

	send_console_command "${master_console_fd:-}" "$command"
	send_console_command "${caves_console_fd:-}" "$command"
}

function wait_for_shards_to_exit()
{
	local timeout="${1:-60}"
	local deadline=$((SECONDS + timeout))
	local pid
	local running

	while true; do
		running=0

		for pid in "${master_pid:-}" "${caves_pid:-}"; do
			if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
				running=1
				break
			fi
		done

		if [ "$running" -eq 0 ]; then
			return 0
		fi

		if [ "$SECONDS" -ge "$deadline" ]; then
			return 1
		fi

		sleep 1
	done
}

function request_graceful_shutdown()
{
	send_console_command "${master_console_fd:-}" "c_shutdown(true)"
	send_console_command "${caves_console_fd:-}" "c_shutdown(true)"
}

function run_low_priority()
{
	if command -v ionice >/dev/null 2>&1; then
		ionice -c2 -n7 nice -n "$auto_backup_nice" "$@"
	else
		nice -n "$auto_backup_nice" "$@"
	fi
}

function query_current_day()
{
	local nonce
	local start_line
	local deadline
	local line

	nonce="$(generate_hex_id 4)"
	start_line="$(wc -l < "$master_log" 2>/dev/null || echo 0)"

	send_console_command \
		"${master_console_fd:-}" \
		"local c=(TheWorld and TheWorld.state and TheWorld.state.cycles); print('AUTOBACKUP_DAY:${nonce}:' .. tostring(c and (c + 1) or -1))"

	deadline=$((SECONDS + 10))

	while [ "$SECONDS" -le "$deadline" ]; do
		line="$(
			sed -n "$((start_line + 1)),\$p" "$master_log" 2>/dev/null \
				| grep "AUTOBACKUP_DAY:${nonce}:" \
				| tail -n 1 || true
		)"

		if [ -n "$line" ]; then
			echo "$line" | sed -nE "s/.*AUTOBACKUP_DAY:${nonce}:(-?[0-9]+).*/\\1/p"
			return 0
		fi

		sleep 1
	done

	return 1
}

function format_day_number()
{
	printf '%04d' "$1"
}

function stream_log_events()
{
	local source="$1"
	local log_file="$2"

	tail -n0 -F "$log_file" 2>/dev/null | while IFS= read -r line; do
		printf '%s\t%s\n' "$source" "$line"
	done
}

function backup_already_exists_for_day()
{
	local day="$1"
	local meta_file

	meta_file="$(printf '%s/%s%s.meta' \
		"$auto_backup_dir" \
		"$auto_backup_name_prefix" \
		"$(format_day_number "$day")")"

	if [ ! -f "$meta_file" ]; then
		return 1
	fi

	grep -qx "world_day=$day" "$meta_file"
}

function prune_old_auto_backups()
{
	local keep_count
	local -a metas
	local old_meta
	local day_token

	keep_count="$auto_backup_max_backups"

	mapfile -t metas < <(
		find "$auto_backup_dir" -maxdepth 1 -type f -name "${auto_backup_name_prefix}[0-9]*.meta" \
			| sed -nE "s#^(.*/${auto_backup_name_prefix}([0-9]+)\.meta)\$#\\2 \\1#p" \
			| sort -n \
			| awk '{print $2}'
	)

	if [ "${#metas[@]}" -le "$keep_count" ]; then
		return
	fi

	for old_meta in "${metas[@]:0:${#metas[@]}-keep_count}"; do
		day_token="$(basename "$old_meta" | sed -nE "s/^${auto_backup_name_prefix}([0-9]+)\.meta$/\\1/p")"
		rm -f "$old_meta" "$auto_backup_dir/${auto_backup_name_prefix}${day_token}.tar.gz"
	done
}

function perform_auto_backup()
{
	local day="$1"
	local day_token
	local archive_path
	local meta_path
	local tmp_archive
	local tmp_meta

	mkdir -p "$auto_backup_dir"

	if backup_already_exists_for_day "$day"; then
		return 0
	fi

	if ! mkdir "$auto_backup_dir/.lock" 2>/dev/null; then
		return 0
	fi

	day_token="$(format_day_number "$day")"
	archive_path="$(printf '%s/%s%s.tar.gz' "$auto_backup_dir" "$auto_backup_name_prefix" "$day_token")"
	meta_path="$(printf '%s/%s%s.meta' "$auto_backup_dir" "$auto_backup_name_prefix" "$day_token")"
	tmp_archive="${archive_path}.tmp"
	tmp_meta="${meta_path}.tmp"

	info "Auto backup triggered for Day $day. Archiving current cluster state."
	announce_cluster_message "${auto_backup_announce_start} Day ${day}."

	if ! run_low_priority tar -C "$dontstarve_dir" -czf "$tmp_archive" "$cluster_name"; then
		rm -f "$tmp_archive" "$tmp_meta"
		rmdir "$auto_backup_dir/.lock" 2>/dev/null || true
		fail "Auto backup tar operation failed."
	fi

	cat > "$tmp_meta" <<EOF
world_day=$day
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

	mv -f "$tmp_archive" "$archive_path"
	mv -f "$tmp_meta" "$meta_path"
	prune_old_auto_backups
	rmdir "$auto_backup_dir/.lock" 2>/dev/null || true

	announce_cluster_message "${auto_backup_announce_end} Day ${day}."
	info "Auto backup stored Day $day: $archive_path"
}

function auto_backup_loop()
{
	(
		local event_pipe="/tmp/dst-autobackup.${BASHPID}.events"
		local day
		local source
		local line
		local master_saved=0
		local caves_saved=0
		local master_stream_pid=""
		local caves_stream_pid=""

		function cleanup_auto_backup_loop()
		{
			if [ -n "$master_stream_pid" ]; then
				kill "$master_stream_pid" 2>/dev/null || true
				wait "$master_stream_pid" 2>/dev/null || true
			fi

			if [ -n "$caves_stream_pid" ]; then
				kill "$caves_stream_pid" 2>/dev/null || true
				wait "$caves_stream_pid" 2>/dev/null || true
			fi

			exec 9>&- 9<&- 2>/dev/null || true
			rm -f "$event_pipe"
		}

		trap cleanup_auto_backup_loop EXIT INT TERM

		validate_auto_backup_config
		mkdir -p "$auto_backup_dir"
		info "Auto backup enabled: every ${auto_backup_interval_days} days, keep ${auto_backup_max_backups} backups."

		rm -f "$event_pipe"
		mkfifo "$event_pipe"
		exec 9<>"$event_pipe"

		stream_log_events "MASTER" "$master_log" > "$event_pipe" &
		master_stream_pid=$!

		stream_log_events "CAVES" "$caves_log" > "$event_pipe" &
		caves_stream_pid=$!

		while IFS=$'\t' read -r source line <&9; do
			if [ "${shutdown_requested:-0}" -eq 1 ]; then
				return 0
			fi

			if ! kill -0 "${master_pid:-}" 2>/dev/null || ! kill -0 "${caves_pid:-}" 2>/dev/null; then
				return 0
			fi

			if [[ "$line" != *"Serializing world: session/"* ]]; then
				continue
			fi

			if [ "$source" = "MASTER" ]; then
				master_saved=1
			elif [ "$source" = "CAVES" ]; then
				caves_saved=1
			fi

			if [ "$master_saved" -ne 1 ] || [ "$caves_saved" -ne 1 ]; then
				continue
			fi

			master_saved=0
			caves_saved=0
			day="$(query_current_day || true)"

			if ! is_non_negative_integer "$day" || [ "$day" -le 0 ]; then
				continue
			fi

			if [ $((day % auto_backup_interval_days)) -ne 0 ]; then
				continue
			fi

			perform_auto_backup "$day"
		done
	)
}

function start_auto_backup_monitor()
{
	if ! is_enabled "$auto_backup_enabled"; then
		info "Auto backup disabled."
		return
	fi

	auto_backup_loop &
	auto_backup_pid=$!
}

function initialize_template_identifiers()
{
	local cluster_ini="$cluster_dir/cluster.ini"
	local caves_server_ini="$cluster_dir/Caves/server.ini"
	local cluster_cloud_id

	if [ ! -f "$template_stamp" ]; then
		if [ -f "$cluster_ini" ]; then
			cluster_cloud_id="$(generate_hex_id 8)"
			sed -i -E \
				"s/^([[:space:]]*cluster_cloud_id[[:space:]]*=[[:space:]]*).*/\\1$cluster_cloud_id/" \
				"$cluster_ini"
			info "Generated unique cluster_cloud_id for this deployment."
		fi

		if [ -f "$caves_server_ini" ] && grep -Eq '^[[:space:]]*id[[:space:]]*=' "$caves_server_ini"; then
			sed -i -E '/^[[:space:]]*id[[:space:]]*=/d' "$caves_server_ini"
			info "Removed hard-coded Caves shard id so DST can auto-generate a unique value."
		fi

		touch "$template_stamp"
	fi
}

function handle_shutdown()
{
	if [ "${shutdown_requested:-0}" -eq 1 ]; then
		return
	fi

	shutdown_requested=1

	info "Shutdown signal received. Asking shards to save and stop."
	request_graceful_shutdown

	if wait_for_shards_to_exit "$shutdown_timeout"; then
		info "Shards stopped cleanly."
	else
		info "Graceful shard shutdown timed out after ${shutdown_timeout}s. Forcing stop."
	fi

	exit 0
}

function seed_default_data_if_needed()
{
	mkdir -p "$dontstarve_dir" "$log_dir"

	if [ ! -d "$cluster_dir" ]; then
		check_for_directory "$default_cluster_dir"
		check_for_directory "$default_mods_dir"

		info "No cluster found. Seeding bundled cluster template and paired mods."
		cp -a "$default_cluster_dir" "$dontstarve_dir/"
		initialize_template_identifiers

		mkdir -p "$mods_dir"
		cp -an "$default_mods_dir/." "$mods_dir/"
	else
		info "Existing cluster found. Skipping bundled cluster template and paired mods."
	fi
}

function prepare_log_rotation()
{
	touch "$steamcmd_log" "$master_log" "$caves_log"

	cat > "$logrotate_conf" <<EOF
"$log_dir"/*.log {
    size $log_max_size
    rotate $log_rotate_count
    missingok
    notifempty
    copytruncate
}
EOF

	logrotate -s "$logrotate_state" "$logrotate_conf" >/dev/null 2>&1 \
		|| fail "Failed to initialize log rotation."

	(
		while true; do
			sleep "$log_rotate_interval"
			logrotate -s "$logrotate_state" "$logrotate_conf" >/dev/null 2>&1 || true
		done
	) &
	logrotate_pid=$!
}

function validate_cluster_files()
{
	check_for_file "$cluster_dir/cluster.ini"
	check_for_file "$cluster_dir/cluster_token.txt"
	check_for_file "$cluster_dir/Master/server.ini"
	check_for_file "$cluster_dir/Caves/server.ini"
}

function update_server_files()
{
	cd "$steamcmd_dir" || fail "Missing $steamcmd_dir directory!"

	check_for_file "$steamcmd_dir/steamcmd.sh"

	info "Updating DST dedicated server files."
	./steamcmd.sh +force_install_dir "$install_dir" +login anonymous +app_update 343050 +quit \
		>> "$steamcmd_log" 2>&1 || fail "SteamCMD update failed. See $steamcmd_log"

	check_for_directory "$install_dir/bin64"
	info "DST dedicated server files are ready."
}

function start_shards()
{
	local -a run_shared
	local master_fd
	local caves_fd

	cd "$install_dir/bin64" || fail "Missing $install_dir/bin64 directory!"
	check_for_file "$install_dir/bin64/dontstarve_dedicated_server_nullrenderer_x64"

	create_console_input "$caves_console_pipe" caves_console_fd
	create_console_input "$master_console_pipe" master_console_fd

	caves_fd="$caves_console_fd"
	master_fd="$master_console_fd"

	run_shared=(./dontstarve_dedicated_server_nullrenderer_x64)
	run_shared+=(-console)
	run_shared+=(-cluster "$cluster_name")
	run_shared+=(-monitor_parent_process $$)

	info "Detailed logs: $log_dir"
	info "Starting shards: Caves, Master"

	"${run_shared[@]}" -shard Caves <&$caves_fd >> "$caves_log" 2>&1 &
	caves_pid=$!

	"${run_shared[@]}" -shard Master <&$master_fd >> "$master_log" 2>&1 &
	master_pid=$!

	info "Shards started."
}

function wait_for_shards()
{
	local status=0
	local exited_shard="Caves"

	wait -n "$caves_pid" "$master_pid" || status=$?

	if ! kill -0 "$master_pid" 2>/dev/null; then
		exited_shard="Master"
	fi

	info "$exited_shard shard exited with status $status. Check $log_dir for details."
	exit "$status"
}

trap cleanup_children EXIT
trap handle_shutdown INT TERM

seed_default_data_if_needed
prepare_log_rotation
validate_cluster_files
update_server_files
start_shards
start_auto_backup_monitor
wait_for_shards
