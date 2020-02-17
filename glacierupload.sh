#!/bin/bash

# dependencies, jq and parallel:
# sudo dnf install jq
# sudo dnf install parallel
# sudo pip install awscli

byteSize=$1
vaultName=$2
accountId=$3
archiveDescription=$4
filePrefix=$5
originalFile=$6

# count the number of files that begin with "part"
fileCount=$(ls -1 | grep "^$filePrefix" | wc -l)
echo "Total parts to upload: " $fileCount

# get the list of part files to upload.  Edit this if you chose a different prefix in the split command
files=$(ls | grep "^$filePrefix")

# initiate multipart upload connection to glacier
init=$(aws glacier initiate-multipart-upload --account-id $accountId --part-size $byteSize --vault-name $vaultName --archive-description $archiveDescription)

echo "---------------------------------------"
# xargs trims off the quotes
# jq pulls out the json element titled uploadId
uploadId=$(echo $init | jq '.uploadId' | xargs)

# create temp file to store commands
touch commands.txt

# create upload commands to be run in parallel and store in commands.txt
i=0
for file in $files 
  do
     byteStart=$((i*byteSize))
     currentFile=$((i+1))
     if [ $currentFile == $fileCount ]
     then
       lastPartByteSize=$(wc -c < "$file")
       byteEnd=$((i*byteSize+lastPartByteSize-1)) 
     else
       byteEnd=$((i*byteSize+byteSize-1))
     fi
     echo aws glacier upload-multipart-part --body $file --range "'"'bytes '"$byteStart"'-'"$byteEnd"'/*'"'" --account-id $accountId --vault-name $vaultName --upload-id $uploadId >> commands.txt
     i=$(($i+1))
     
  done

# run upload commands in parallel
#   --load 100% option only gives new jobs out if the core is than 100% active
#   -a commands.txt runs every line of that file in parallel, in potentially random order
#   --notice supresses citation output to the console
#   --bar provides a command line progress bar
parallel --load 100% -a commands.txt --no-notice --bar

echo "List Active Multipart Uploads:"
echo "Verify that a connection is open:"
aws glacier list-multipart-uploads --account-id $accountId --vault-name $vaultName

# calculate file tree hash
fileTreeHash=$(./treehash $originalFile)

# end the multipart upload
archiveSize=$(wc -c < "$originalFile")
aws glacier complete-multipart-upload --account-id $accountId --vault-name $vaultName --upload-id $uploadId --checksum $fileTreeHash --archiveSize $archiveSize

# list open multipart connections
echo "------------------------------"
echo "List Active Multipart Uploads:"
echo "Verify that the connection is closed:"
aws glacier list-multipart-uploads --account-id $accountId --vault-name $vaultName

#echo "-------------"
#echo "Contents of commands.txt"
#cat commands.txt
echo "--------------"
echo "Deleting temporary commands.txt file"
rm commands.txt


