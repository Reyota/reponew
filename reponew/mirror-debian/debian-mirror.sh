#!/bin/bash
set -euo pipefail;

#A considerably simpler take on apt-mirror - parses the Packages files like apt-mirror, but then builds a file of .debs to download, which is then passed to rsync which does the rest.
#Saves the overhead of downloading each file over HTTP and considerably simpler to debug. Can now be configured using a file containing paths instead of running rsync many times in a loop.
#Just like apt-mirror, capable of running on only one Ubuntu release to save space.
#Author: Rob Johnson
#Date: 2017-09-20

syncDate=$(date +%F);

#Adapt as necessary to your package mirror setup
sourceFolder='/home/reponew/mirror-debian/mirror-debian.d';
baseDirectory="/mnt/mirror";
#New Feature
telegram_token="$token-telegram"  # Ganti dengan token bot Telegram Anda
chat_id="$chatid-telegram"           # Ganti dengan Chat ID Anda
log_file_success1="/home/log/debianmain-pool-$syncDate.log"  # Log file yang ingin dikirim
log_file_success2="/home/log/debianmainnew-dists--$syncDate.log"  # Log file yang ingin dikirim

# Fungsi untuk mengirim pesan ke Telegram
send_telegram_message() {
    local message=$1
    curl -s -X POST "https://api.telegram.org/bot$telegram_token/sendMessage" \
    -d chat_id="$chat_id" \
    -d text="$message" \
    -d parse_mode="Markdown"
}
# Notifikasi bahwa skrip telah dimulai
start_message="🚀 *Mirror sync Debian Security Updates* started on $syncDate.%0A Syncing process has begun."
send_telegram_message "$start_message"

#Basic checks
if [[ ! -d "$sourceFolder" ]]; then
	echo "Source folder $sourceFolder does not exist!"
	send_telegram_message "❌*Source folder $sourceFolder *does not exist!" #New Feature
	exit 1;

elif [[ $(ls -1 "$sourceFolder"/* | wc -l) -eq 0 ]]; then
    echo "No master source file(s) found in $sourceFolder, create one and add name, releases, repositories and architectures per README." 1>&2;
    send_telegram_message "❌ *No master source file(s) found in $sourceFolder *, create one and add name, releases, repositories and architectures per README." #New Feature
    exit 1;
elif [[ ! $(which rsync) ]] || [[ ! $(which sed) ]] || [[ ! $(which awk) ]]; then
	echo "Missing one or more of required tools 'rsync', 'sed' and 'awk' (or they are not in the PATH for this user)." 1>&2;
	send_telegram_message "❌ *Error:* Missing required tools (rsync, sed, awk)!"
	exit 1;
elif [[ ! $(which gunzip) ]] && [[ ! $(which xzcat) ]]; then
	echo "Warning: missing both 'gunzip' and 'xzcat', required to work with certain repositories that do not provide uncompressed Packages lists. This may not work with your chosen repository. Install gzip and/or xz for best compatibility." 1>&2;
fi

#Add a marker for a second APT mirror to look for - if the sync falls on its face, can drop this out of the pair and sync exclusively from the mirror until fixed
#if [[ -f $baseDirectory/debian/lastSuccessnew-updates ]]; then
if [[ -f "/mnt/mirror/debian/lastSuccessnew-updates" ]]; then
	rm -v "/mnt/mirror/debian/lastSuccessnew-updates";
fi
for sourceServer in "$sourceFolder"/*
do
	source "$sourceServer";
	if [[ -z "$name" ]] || [[ -z "$releases" ]] || [[ -z "$repositories" ]] || [[ -z "$architectures" ]]
	then
		echo "Error: $sourceServer is missing one or more of 'name', 'releases', 'repositories' or 'architectures' entries! Skipping." 1>&2;
		send_telegram_message "❌ *Error:* Missing configuration in $sourceServer!"
		continue;
	fi

	masterSource=$(basename "$sourceServer");
	#File to build a list of files to rsync from the remote mirror - will contain one line for every file in the dists/ to sync
	filename="packages-$masterSource-$syncDate.txt";

	echo "$syncDate $(date +%T) Starting, exporting to /tmp/$filename";

	#In case leftover from testing or failed previous run
	if [[ -f "/tmp/$filename" ]]; then
		rm -v "/tmp/$filename";
	fi

	echo "$(date +%T) Syncing releases";
	localPackageStore="$baseDirectory/$name";
	mkdir -p "$localPackageStore/dists"

	echo -n ${releases[*]} | sed 's/ /\n/g' | rsync --no-motd --delete-during --archive --recursive --human-readable --bwlimit=45m --log-file="/home/log/debianmainnew-dists--$syncDate".log --files-from=- $masterSource::"$name/dists/" "$localPackageStore/dists/";
	echo -n ${may[*]} | sed 's/ /\n/g' | rsync --no-motd --delete-during --archive --recursive --human-readable --bwlimit=45m --files-from=- $masterSource::"$name/" "$localPackageStore/";

	echo "$(date +%T) Generating package list";
	#rather than hard-coding, use a config file to run the loop. The same config file as used above to sync the releases
	for release in ${releases[*]}; do
		for repo in ${repositories[*]}; do
			for arch in ${architectures[*]}; do
				if [[ ! -f "$localPackageStore/dists/$release/$repo/binary-$arch/Packages" ]]; then  #uncompressed file not found
					if [[ $(which gunzip) ]]; then #See issue #5 - some distros don't provide gunzip by default but have xz
					  if [[ -f "$localPackageStore/dists/$release/$repo/binary-$arch/Packages.gz" ]]; then
							packageArchive="$localPackageStore/dists/$release/$repo/binary-$arch/Packages.gz";
							echo "$(date +%T) Extracting $release $repo $arch Packages file from archive $packageArchive";
							if [[ -L "$packageArchive" ]]; then #Some distros (e.g. Debian) make Packages.gz a symlink to a hashed filename. NB. it is relative to the binary-$arch folder
								echo "$(date +%T) Archive is a symlink, resolving";
								packageArchive=$(readlink $packageArchive | sed --expression "s_^_${packageArchive}_" --expression 's/Packages\.gz//');
							fi
							gunzip <"$packageArchive" >>"$localPackageStore/dists/$release/$repo/binary-$arch/Packages";
						fi
						echo "Checking for xzcat availability"
					elif [[ $(which xzcat) ]]; then
						echo "Found xzcat, checking if Packages.xz exists..."
						if [[ -f "$localPackageStore/dists/$release/$repo/binary-$arch/Packages.xz" ]]; then
							echo "Packages.xz exists, extracting now..."
							packageArchive="$localPackageStore/dists/$release/$repo/binary-$arch/Packages.xz";
							echo "$(date +%T) Extracting $release $repo $arch Packages file from archive $packageArchive";
							if [[ -L "$packageArchive" ]]; then #Same as above
								echo "$(date +%T) Archive is a symlink, resolving";
								packageArchive=$(readlink $packageArchive | sed --expression "s_^_${packageArchive}_" --expression 's/Packages\.xz//');
							fi
							xzcat <"$packageArchive" >>"$localPackageStore/dists/$release/$repo/binary-$arch/Packages";
						fi
					else
						echo "xzcat not found in path"
						echo "$(date +%T) Error: uncompressed package list not found in remote repo and decompression tools for .gz or .xz files not found on this system, aborting. Please install either gunzip or xzcat to use this script." 1>&2;
						exit 1;
					fi
					echo "$(date +%T) Extracting packages from $release $repo $arch";
					if [[ -s "$localPackageStore/dists/$release/$repo/binary-$arch/Packages" ]]; then #Have experienced zero filesizes for certain repos
						awk '/^Filename: / { print $2; }' "$localPackageStore/dists/$release/$repo/binary-$arch/Packages" >> "/tmp/$filename";
					else
						echo "$(date +%T) Package list is empty, skipping";
					fi
				fi
			done
		done
	done

	echo "$(date +%T) Deduplicating";

	sort --unique "/tmp/$filename" > "/tmp/$filename.sorted";
	rm -v "/tmp/$filename";
	mv -v "/tmp/$filename.sorted" "/tmp/$filename";

	echo "$(wc -l /tmp/$filename | awk '{print $1}') files to be sync'd";

	echo "$(date +%T) Running rsync";

	#rsync may error out due to excessive load on the source server, so try up to 3 times
	set +e;
	attempt=1;
	exitCode=1;

	while [[ $exitCode -gt 0 ]] && [[ $attempt -lt 4 ]];
	do
		SECONDS=0;
		rsync --copy-links --files-from="/tmp/$filename" --no-motd --delete-during --archive --recursive --human-readable --log-file="/home/log/debianmain-pool-$syncDate".log $masterSource::$name "$localPackageStore/" 2>&1;
		exitCode=$?;
		if [[ $exitCode -gt 0 ]]; then
			waitTime=$((attempt*300)); #increasing wait time - 5, 10 and 15 minutes between attempts
			echo "$(date +%T) rsync attempt $attempt failed with exit code $exitCode, waiting $waitTime seconds to retry" 1>&2;
			sleep $waitTime;
			let attempt+=1;
		fi
	done

	set -e;

	#Exiting here will stop the lastSuccess file being created, and will stop APT02 running its own sync
	if [[ $exitCode -gt 0 ]]; then
		echo "rsync failed all 3 attempts, erroring out" 1>&2;
		send_telegram_message "❌ *Rsync Debian Archive Main failed* all 3 attempts for $masterSource!" #New Feature
		exit 2;
	fi

	echo "$(date +%T) Sync from $masterSource complete, runtime: $SECONDS s";
	# Kirimkan pesan log sukses ke Telegram
	success_message="✅ *Rsync Debian Archive Main for $masterSource completed successfully* on $syncDate. Runtime: $SECONDS seconds. "
	send_telegram_message "$success_message"

	echo "$(date +%T) Deleting obsolete packages";

	#Build a list of files that have been synced and delete any that are not in the list
#	find "$localPackageStore/pool/" -type f | { grep -Fvf "/tmp/$filename" || true; } | xargs --no-run-if-empty -I {} rm -v {}; # '|| true' used here to prevent grep causing pipefail if there are no packages to delete - grep normally returns 1 if no files are found

#	echo "$(date +%T) Completed $masterSource";

#	rm -v "/tmp/$filename";
done
#touch "$baseDirectory/lastSuccess";
	touch "$baseDirectory/$name/lastSuccessnew-updates";

	echo "$(date +%T) Inserting log data into lastSuccessnew-updates"

	cat "$log_file_success1" "$log_file_success2" >> "$baseDirectory/$name/lastSuccessnew-updates"
# Notifikasi selesai skrip
	end_message="✅  *Mirror sync Debian Archive Main* script finished on $syncDate.%0A All processes completed."
	send_telegram_message "$end_message"

echo "$(date +%T) Finished";
