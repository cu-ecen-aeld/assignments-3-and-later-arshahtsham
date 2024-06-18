#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
    echo "Error: Two arguments required. Usage: writer.sh <writefile> <writestr>"
    exit 1
fi

writefile=$1
writestr=$2

# Create the directory path if it doesn't exist
mkdir -p "$(dirname "$writefile")"

# Attempt to create the file and write the string to it
if echo "$writestr" > "$writefile"; then
    echo "Successfully wrote to $writefile"
else
    echo "Error: Could not create or write to $writefile"
    exit 1
fi

