#!/bin/bash
# Requires synapseclient via pypi

set -eou pipefail

# Take in a TSV as input
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
tail -n +2 $manifest_tsv | while IFS=$'\t' read -r input_filepath synapse_id_dest other_args
do
	expanded_filepaths="$(find $input_filepath)"

	# If find returns an error, error out.
	if [ $? -ne 0 ]; then
		# Capture find's error message.
		# TODO
		echo "Error: The following filepath (input to `find`) is invalid: ${input_filepath}"
		exit 1
	fi

	# Iterate through each of the expanded_filepaths
	for expanded_filepath in $expanded_filepaths
	do
		# Append the transformed row to the transformed_tsv
		echo -e "${expanded_filepath}\t${synapse_id_dest}\t${other_args}" >> $transformed_tsv
	done

done

cat $transformed_tsv
echo "Transformed manifest file written to $transformed_tsv"

synapse sync --manifest $transformed_tsv
