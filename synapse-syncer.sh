#!/bin/bash
# Requires synapseclient via pypi
# TODO: have the user instead do:
# filename synapse_id
# folder synapse_id (the folder will be recursed entirely)
# file synapse_id
# Where you should separate the folder rows from the file rows, and for each folder you run synapse manifest <folder_path> --parent-id <synapse_id>, where the folder begins from that id.

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

	while IFS=$'\t' read -r input_filepath synapse_id_dest; do

		# Ignore if input_filepath begins with a #, indicating it is a comment.
		if [[ $input_filepath == \#* ]]; then
			continue
		fi

		if [ -f $input_filepath ]; then
			echo -e "${input_filepath}\t${synapse_id_dest}" >> $transformed_tsv
		elif [ -d $input_filepath ]; then
			# Append the transformed row to the transformed_tsv
			# Expand using `manifest`
			set +e
			generated_folder_manifest=$(mktemp)
			manifest_stdout=$(mktemp)
			manifest_stderr=$(mktemp)
			python3 /usr/local/bin/synapse manifest $input_filepath --parent-id $synapse_id_dest --manifest-file $generated_folder_manifest > $manifest_stdout 2> $manifest_stderr
			manifest_exit_code=$?
			set -e

			# Handle the synapse sync exit status
			if [ $manifest_exit_code -ne 0 ]; then
				log_to_user "$user" "$(get_log_prefix) Failed to sync manifest file: $manifest_tsv due to the following error: $(cat $manifest_stderr). Please correct it in order to sync the manifest file."
				set +e
				return 1
				set -e
			fi

			echo "$(get_log_prefix) Intermediate manifest file for $user's folder $input_filepath written to $generated_folder_manifest:/n$(cat $generated_folder_manifest)"

			tail -n +2 $generated_folder_manifest >> $transformed_tsv
		else
			does_manifest_have_invalid_paths=true
			invalid_filepaths+=($input_filepath)
		fi
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

	# Remove carriage returns.
	sed -i 's/\r//g' $transformed_tsv

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

	echo "$(get_log_prefix) Sync stdout:\n$(cat $sync_stdout)"

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