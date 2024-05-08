#!/bin/bash
# Requires synapseclient via pypi

set -eou pipefail

# Globals
MANIFEST_BASENAME=".synapse-manifest.tsv"
is_local_only=false
local_log_file="/users/${USER}/$(basename $0).${USER}.log"

get_log_prefix() {
	echo "[$(date)]:"
}

log_to_user() {
	user=$1
	message=$2
	log_file="/var/log/$(basename $0).${user}.log"
	if [[ $is_local_only == true ]]; then
		log_file="$local_log_file"
	fi
	echo $message | tee -a $log_file
}

sync_manifest() {
	manifest_tsv=$1
	user=$2

	# Check that the file exists
	if [ ! -f $manifest_tsv ]; then
		echo "File not found: $manifest_tsv"
		return 1
	fi

	transformed_tsv=$(mktemp)

	head -n 1 $manifest_tsv > $transformed_tsv

	# Transform the manifest file into a format that expands folders into individual filepaths.
	# We do this because `synapse sync` doesn't support syncing folders.
	does_manifest_have_invalid_paths=false
	invalid_filepaths=()

	while IFS=$'\t' read -r input_filepath synapse_id_dest other_args; do

		# Ignore if input_filepath begins with a #, indicating it is a comment.
		if [[ $input_filepath == \#* ]]; then
			continue
		fi

		find_stdout=$(mktemp)
		find_stderr=$(mktemp)
		set +e
		find $input_filepath > $find_stdout 2> $find_stderr
		set -e
		find_exit_code=$?

		# Error handling.
		if [ $find_exit_code -ne 0 ]; then
			does_manifest_have_invalid_paths=true
			if ! grep -q "No such file or directory" $find_stderr; then
				# Capture find's error message.
				echo "Error: The following \`find\` operation failed for an unknown reason: ${input_filepath}. Please correct it and run this again."
			fi
			invalid_filepaths+=($input_filepath)
			continue
		fi

		expanded_filepaths=$(cat $find_stdout)
		# Iterate through each of the expanded_filepaths
		for expanded_filepath in $expanded_filepaths
		do
			# Append the transformed row to the transformed_tsv
			echo -e "${expanded_filepath}\t${synapse_id_dest}\t${other_args}" >> $transformed_tsv
		done

	done < <(tail -n +2 "$manifest_tsv")

	# Print out the invalid filepaths and exit if there are any.
	if [ "$does_manifest_have_invalid_paths" = true ]; then
		echo "Error: The following filepaths are invalid or could not be found. Please correct them and run this again:"
		# Iterate through each of the invalid_filepaths
		for invalid_filepath in "${invalid_filepaths[@]}"; do
			echo $invalid_filepath
		done
		set +e
		return 1
		set -e
	fi

	echo "$(get_log_prefix) Transformed manifest file for $user written to $transformed_tsv:"
	cat $transformed_tsv

	set +e
	sync_stdout=$(mktemp)
	sync_stderr=$(mktemp)
	python3 /usr/local/bin/synapse sync $transformed_tsv > $sync_stdout 2> $sync_stderr
	sync_exit_code=$?
	set -e

	# Handle the synapse sync exit status
	if [ $sync_exit_code -ne 0 ]; then
		log_to_user "$user" "$(get_log_prefix) Failed to sync manifest file: $manifest_tsv due to the following error: $(cat $sync_stderr). Please correct it in order to sync the manifest file."
		set +e
		return 1  # Returning a different error code for sync failures
		set -e
	fi

	echo "Transformed manifest file successfully synced: $transformed_tsv"
}

main() {

	while [[ "$#" -gt 0 ]]; do
		case "$1" in
			--local)
				is_local_only=true
				echo "Running in local mode- in which only the user's own manifest file is synced. Logging to $local_log_file"
				shift
				;;
			*)
				echo "Unknown option: $1"
				exit 1
				;;
		esac
	done

	# Iterate through each user, running the sync_manifest function on their manifest file.
	user_dirs=$(find /users -maxdepth 1 -mindepth 1 -type d)
	for user_dir in $user_dirs; do

		user=$(basename $user_dir)

		if [[ $is_local_only == true && $user != $USER ]]; then
			continue
		fi

		manifest_file="${user_dir}/${MANIFEST_BASENAME}"

		echo "$(get_log_prefix) Searching for manifest file at $manifest_file"
		if [ -f $manifest_file ]; then
			sync_manifest $manifest_file $user
			echo "exit code is $?"
			if [ $? -eq 0 ]; then
				log_to_user "$user" "$(get_log_prefix) Successfully synced manifest file: $manifest_file"
			else
				log_to_user "$user" "$(get_log_prefix) Failed to sync manifest file: $manifest_file"
			fi
		fi
	done
}

# Take in a TSV as input
main "$@"