#!/bin/bash

# The program will execute according to the following flow
# --------------------------------------------------------------------------------------------------------------
# Generate aes 256 bit keysize with command below
# 1. Generate EAS key (keysize = 256bit = 32 byte)
# > openssl rand -hex 32 > aes.key
# *                                    ---------------------------------                                       *
# 2. Encrypt the data after the -n segment
# > echo -n "password" | openssl enc -aes-256-cbc -pbkdf2 -iter 10000 -out encrypted_data.txt -pass file:aes.key
# Or
# > data=password
# > openssl enc -aes-256-cbc -pbkdf2 -iter 10000 -in <(echo "$data") -out encrypted_data.txt -pass file:aes.key
# *                                   ---------------------------------                                        *
# 3. Decrypt the data from encrypted_data.txt file
# > openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -in encrypted_data.txt -pass file:aes.key
# *                                   ---------------------------------                                        *

VERSION="1.0.4"

# Declare variables as a global variable
sourceslot=""
keyname=""
targetslot=""
sourceip=""
targetip=""

# Set logfile name with date
logfile="$PWD/logs/hsm_operations_$(date '+%Y-%m-%d').log"

# Function to log messages with timestamp and username
function log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [User: $USER] $1" | tee -a $logfile
}

log "----------------------------------------------------------------------------------------"
log "                       AUTOMATIC KEY SYNCING APPLICATION (v$VERSION)                       "
log "----------------------------------------------------------------------------------------"

# Check if config.properties file exists
if [ -f "config.properties" ]; then
    # Read values from config.properties file
    sourceip=$(grep -E '^sourceip=' config.properties | cut -d'=' -f2)
    sourceslot=$(grep -E '^sourceslot=' config.properties | cut -d'=' -f2)
    targetip=$(grep -E '^targetip=' config.properties | cut -d'=' -f2)
    targetslot=$(grep -E '^targetslot=' config.properties | cut -d'=' -f2)
fi

log "Checking... current config.properties file"
log "Source HSM IP: $sourceip"
log "Source SLOT: $sourceslot"
log "Target HSM IP: $targetip"
log "Target SLOT: $targetslot"

# Encrypt password function
function encrypt_text() {
    openssl rand -hex 32 > aes.key
    log "This function will generate a 256bit AES key and encrypt the HSM access PIN, everything is made permanent so you don't need to do this again."
    log "----------------------------------------------------------------------------------------"
    log "Enter the PIN code, this PIN code will be encrypted and then used for backing up and restoring the keys to HSM:"
    read -s data
    openssl enc -aes-256-cbc -pbkdf2 -iter 10000 -in <(echo "$data") -out encrypted_data.txt -pass file:aes.key
    log "the PIN has been encrypted and save to file:"
    log "encrypted_data.txt"
    ls -alh | grep -B0 -A0 -E "aes.key|encrypted_data.txt"
}

# Backup hsm
function backup_hsm() {
    if [ -f "encrypted_data.txt" ]; then
        pin=$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -in encrypted_data.txt -pass file:aes.key)
        log "Listkeys from source HSM $sourceip"
        cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot ListKeys
        
        # Ask if you want to backup all or 1 key
        read -p "Do you want to backup all keys (all) or just 1 key (1)? " choice
        
        if [ "$choice" = "all" ]; then
            log "Backing up all keys..."
            cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot Name=* OutDir=$PWD backupkey
        else
            log "Enter the name of the key you want to back up"
            read keyname
            cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot Name=$keyname OutDir=$PWD backupkey
        fi
        
        pin=""
    else
        log "File encrypted_data.txt not found. Please repeat option 1. Encrypt PIN"
    fi
}

# Restore hsm
function restore_hsm() {
    if [ -f "encrypted_data.txt" ]; then
        pin=$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -in encrypted_data.txt -pass file:aes.key)
        log "Listing... keys present in the current directory"
        log "----------------------------------------------------------------------------------------"
        ls -alh *.kbk | tee -a $logfile
        log "----------------------------------------------------------------------------------------"
        # Save a list of .kbk files into an array
        kbk_files=($(ls -a *.kbk))
        total_keys=${#kbk_files[@]}
        log "Found $total_keys keys present in the current directory"

        log "Enter the name of the backup's key you want to restore into HSM with IP: $targetip"
        log "The file name must contain the .kbk part (example: CXIKey.kbk)"
        log "Or type 'all' to restore all keys"
        read keyfile
        # Check if user enter "all"
        if [ "$keyfile" == "all" ]; then
            restored_keys=0
            # Loop through the array and execute cxitool for each file
            for file in "${kbk_files[@]}"; do
                cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot Restorekey=$file | tee -a $logfile
                log "$((restored_keys+1)) key(s) out of $total_keys have been restored to HSM $targetip"
                ((restored_keys++))
            done
        else
            # Perform restore for 1 file
            #pin=""
            cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot Restorekey=$keyfile | tee -a $logfile
            log "1 key name $keyfile has been restored to HSM $targetip"
        fi

        log "Listing keys from source HSM $targetip"
        cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot ListKeys | tee -a $logfile
        pin=""
    else
        log "File encrypted_data.txt not found. Please repeat option 1. Encrypt PIN"
    fi
}

function backup_restore() {
    if [ -f "encrypted_data.txt" ]; then
        pin=$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -in encrypted_data.txt -pass file:aes.key)

        # Backup all keys
        log "Listing keys from source HSM $sourceip"
        cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot ListKeys | tee -a $logfile

        log "Backing up all keys to the current directory..."
        cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot Name=* OutDir=$PWD backupkey | tee -a $logfile

        # Restore all keys
        log "Listing backup key files in the current directory"
        log "----------------------------------------------------------------------------------------"
        ls -alh *.kbk | tee -a $logfile
        log "----------------------------------------------------------------------------------------"

        log "Restoring all keys to target HSM $targetip"
        restored_keys=0
        for file in *.kbk; do
            cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot Restorekey=$file | tee -a $logfile
            log "$((restored_keys+1)) key(s) out of $(ls -1 *.kbk | wc -l) have been restored to HSM $targetip"
            ((restored_keys++))
        done
        
        log "Listing keys from target HSM $targetip"
        cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot ListKeys | tee -a $logfile
        source_array_func | tee -a $logfile
        target_array_func | tee -a $logfile
        compare_arrays_func | tee -a $logfile
        pin=""
    else
        log "File encrypted_data.txt not found. Please repeat option 1. Encrypt PIN"
    fi
}

# Function to run cxitool and parse the output into an array
function source_array_func() {
    local cxitool_output
    local IFS=$'\n'

    # Example command to get the output of cxitool (replace with actual command)
    cxitool_output=$(cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot ListKeys)

    # Parse the output into an array, skipping the first 3 lines (header)
    source_array=($(echo "$cxitool_output" | tail -n +4 | sed 's/[[:space:]]*$//'))

    # Echo and print the parsed output
    echo "Parsed cxitool output for source:"
    for line in "${source_array[@]}"; do
        echo "$line"
    done
    
    # Check the number of lines in the array
    num_lines=${#source_array[@]}
    echo "Number of lines in source_array: $num_lines"

    # Declare an array to store source_key_infos
    declare -a source_keys_array

    # Accessing elements from the array
    for ((i=0; i<num_lines; i++)); do
        line=${source_array[i]}
        group=$(echo "$line" | awk '{print $5}')
        name=$(echo "$line" | awk '{print substr($0, 50, 33)}' | sed 's/ *$//')
        
        # Run the cxitool command with the extracted name and group
        source_key_info=$(cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$group Name=$name keyinfo)
    
        # Store the source_key_info in the source_keys_array
        source_keys_array[i]="$source_key_info"
    done

    # Optionally, echo all source_key_infos at the end
    echo "All source keypair details:"
    for ((i=0; i<num_lines; i++)); do
        echo "Source keyinfo $((i+1)): ${source_keys_array[i]}"
    done

    # Export source array and key infos to global variables
    export source_array
    export source_keys_array
    export num_lines
}

# Function to run cxitool and parse the output into an array
function target_array_func() {
    local cxitool_output_target
    local IFS=$'\n'

    # Example command to get the output of cxitool for target (replace with actual command)
    cxitool_output_target=$(cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot ListKeys)

    # Parse the output into an array, skipping the first 3 lines (header)
    target_array=($(echo "$cxitool_output_target" | tail -n +4 | sed 's/[[:space:]]*$//'))

    # Echo and print the parsed output for target
    echo "Parsed cxitool output for target:"
    for line in "${target_array[@]}"; do
        echo "$line"
    done
    
    # Check the number of lines in the target array
    num_lines_target=${#target_array[@]}
    echo "Number of lines in target_array: $num_lines_target"

    # Declare an array to store target_key_infos
    declare -a target_keys_array

    # Accessing elements from the target array
    for ((i=0; i<num_lines_target; i++)); do
        line=${target_array[i]}
        group=$(echo "$line" | awk '{print $5}')
        name=$(echo "$line" | awk '{print substr($0, 50, 33)}' | sed 's/ *$//')

        # Run the cxitool command with the extracted name and group
        target_key_info=$(cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$group Name=$name keyinfo)
    
        # Store the target_key_info in the target_keys_array
        target_keys_array[i]="$target_key_info"
    done

    # Optionally, echo all target_key_infos at the end
    echo "All target keypair details:"
    for ((i=0; i<num_lines_target; i++)); do
        echo "Target keyinfo $((i+1)): ${target_keys_array[i]}"
    done

    # Export target array and key infos to global variables
    export target_array
    export target_keys_array
    export num_lines_target
}

function compare_arrays_func() {
    # Compare the arrays and find matching lines
    echo "Matching lines and their keyinfos:"
    for ((i=0; i<num_lines; i++)); do
        for ((j=0; j<num_lines_target; j++)); do
            if [[ "${source_array[i]}" == "${target_array[j]}" ]]; then
                echo "Matching line: ${source_array[i]}"
                echo "Source keyinfo: ${source_keys_array[i]}"
                echo "Target keyinfo: ${target_keys_array[j]}"
            fi
        done
    done
}

# Menu
while true; do
    log "----------------------------------------------------------------------------------------"
    log "Choose function:"
    log "1. Encrypt PIN"
    log "2. Backup HSM"
    log "3. Restore HSM"
    log "4. Automatic backup all keys from HSM $sourceip to $targetip "
    log "5. Exit."
    read -p "Choose (1-5): " choice

    case $choice in
        1)
            log "----------------------------------------------------------------------------------------"
            log "Selected option: 1. Encrypt PIN"
            encrypt_text
            ;;
        2)
            log "----------------------------------------------------------------------------------------"
            log "Selected option: 2. Backup HSM"
            backup_hsm
            ;;
        3)
            log "----------------------------------------------------------------------------------------"
            log "Selected option: 3. Restore HSM"
            restore_hsm
            ;;
        4)
            log "Selected option: 4. Automatic backup all keys from HSM $sourceip to $targetip"
            backup_restore
            ;;
        5)
            log "----------------------------------------------------------------------------------------"
            log "Selected option: 5. -> Exit."
            exit 0
            ;;
        *)
            log "Invalid selection. Please try again."
            ;;
    esac
done
