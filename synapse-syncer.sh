#!/bin/bash
# Requires synapseclient via pypi

set -eou pipefail

main() {
	manifest_tsv=$1

	# Check that the file exists
	if [ ! -f $manifest_tsv ]; then
		echo "File not found: $manifest_tsv"
		exit 1
	fi

	transformed_tsv=$(mktemp)

	head -n 1 $manifest_tsv > $transformed_tsv

	# Transform the manifest file into a format that expands folders into individual filepaths.
	# We do this because `synapse sync` doesn't support syncing folders.
	does_manifest_have_invalid_paths=false
	invalid_filepaths=()

	while IFS=$'\t' read -r input_filepath synapse_id_dest other_args; do

		find_stdout="output.txt"
		find_stderr="error.txt"
		set +e
		find $input_filepath > $find_stdout 2> $find_stderr
		find_exit_code=$?
		set -e

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
		for invalid_filepath in "${invalid_filepaths[@]}"
		do
			echo $invalid_filepath
		done
		exit 1
	fi

	cat $transformed_tsv
	echo "Transformed manifest file written to $transformed_tsv"

	python3 /usr/local/bin/synapse sync $transformed_tsv
}

# Take in a TSV as input
main $1