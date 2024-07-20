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

VERSION="1.0.7"

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

config_file="config.properties"

# Function to create config.properties file with default values
function create_config_file() {
    echo "sourceip=3001@127.0.0.1" > $config_file
    echo "sourceslot=SLOT_0000" >> $config_file
    echo "targetip=3001@127.0.0.1" >> $config_file
    echo "targetslot=SLOT_0000" >> $config_file
    log "Created default config.properties file."
}

# Check if config.properties file exists
if [ ! -f "$config_file" ]; then
    create_config_file
fi

# Read values from config.properties file
sourceip=$(grep -E '^sourceip=' $config_file | cut -d'=' -f2)
sourceslot=$(grep -E '^sourceslot=' $config_file | cut -d'=' -f2)
targetip=$(grep -E '^targetip=' $config_file | cut -d'=' -f2)
targetslot=$(grep -E '^targetslot=' $config_file | cut -d'=' -f2)

# Function to log current configuration
function log_config() {
    log "Checking current config.properties...:"
    log "Source HSM IP: $sourceip"
    log "Source SLOT: $sourceslot"
    log "Target HSM IP: $targetip"
    log "Target SLOT: $targetslot"
}

# Log current configuration
log_config

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
        log "----------------------------------------------------------------------------------------"
        log "                               BACKING-UP-KEYS PROCESSING                               "
        
        # Ask if you want to backup all or 1 key
        read -p "Do you want to backup all keys (all) or just 1 key (1)? " choice
        
        if [ "$choice" = "all" ]; then
            log "Backing up all keys..."
            cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot Name=* OutDir=$PWD backupkey && echo -n "to current directory folder"
        else
            cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot ListKeys
            log "Enter the name of the key you want to back up"
            read keyname
            cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot Name=$keyname OutDir=$PWD backupkey && echo -n "to current directory folder"
        fi
        
        pin=""
    else
        log "File encrypted_data.txt not found. Please repeat option 1. Encrypt PIN"
    fi
}

function demo_key_generation() {
    if [ -f "encrypted_data.txt" ]; then
        pin=$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -in encrypted_data.txt -pass file:aes.key)
        
        log "Name=ECDSA_DEMO_KEY Export=Allow Usage=SIGN,VERIFY GenerateKey=EC,secp256r1 has been generated"
        cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot Name=ECDSA_DEMO_KEY Export=Allow Usage=SIGN,VERIFY Overwrite=1 GenerateKey=EC,secp256r1
        log "Name=RSA_DEMO_KEY Export=Allow Usage=ENCRYPT,DECRYPT GenerateKey=RSA,2048 has been generated"
        cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot Name=RSA_DEMO_KEY Export=Allow Usage=ENCRYPT,DECRYPT Overwrite=1 GenerateKey=RSA,2048
        log "Name=AES_DEMO_KEY Usage=WRAP,UNWRAP GenerateKey=AES,256 has been generated"
        cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot Name=AES_DEMO_KEY Usage=WRAP,UNWRAP Overwrite=1 GenerateKey=AES,256
        log "Name=DSA_DEMO_KEY GenerateKey=DSA,2048/256 has been generated"
        cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot Name=DSA_DEMO_KEY Overwrite=1 GenerateKey=DSA,2048/256
        
        pin=""
    else
        log "File encrypted_data.txt not found. Please repeat option 1. Encrypt PIN"
    fi
}

# Restore hsm
function restore_hsm() {
    if [ -f "encrypted_data.txt" ]; then
        pin=$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -in encrypted_data.txt -pass file:aes.key)
        log "----------------------------------------------------------------------------------------"
        log "                                RESTORE-KEYS PROCESSING                                 "
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
                log "Select option: restore $file key"
                cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot Restorekey=$file | tee -a $logfile
                log "$((restored_keys+1)) key(s) out of $total_keys have been restored to HSM $targetip"
                ((restored_keys++))
            done
        else
            # Perform restore for 1 file
            #pin=""
            log "Select option: restore all keys"
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

        log "----------------------------------------------------------------------------------------"
        log "                               BACKING-UP-KEYS PROCESSING                               "
        cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot Name=* OutDir=$PWD backupkey && echo -n "to current directory folder" | tee -a $logfile

        log "\nListing backup key files in the current directory"
        log "----------------------------------------------------------------------------------------"
        ls -alh *.kbk | tee -a $logfile
        log "----------------------------------------------------------------------------------------"
        
        # Compare arrays before restoring keys
        source_array_func
        target_array_func
        log "----------------------------------------------------------------------------------------"
        log "                                RESTORE-KEYS PROCESSING                                 "
        log "Listing keys from target HSM $targetip"
        cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot ListKeys | tee -a $logfile
        compare_arrays_func | tee -a $logfile

        # Ask for confirmation before proceeding with restore
        read -p "Press Enter to confirm restoring keys to target HSM $targetip (or Ctrl+C to cancel)."

        # Restore all keys
        log "Restoring all keys to target HSM $targetip"
        restored_keys=0
        for file in *.kbk; do
            cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot Restorekey=$file | tee -a $logfile
            log "$((restored_keys+1)) key(s) out of $(ls -1 *.kbk | wc -l) have been restored to HSM $targetip"
            ((restored_keys++))
        done
        
        log "Listing keys from target HSM $targetip"
        cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot ListKeys | tee -a $logfile
        
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

    # Check the number of lines in the array
    num_lines_source=${#source_array[@]}  # Rename num_lines to num_lines_source

    # Declare an array to store source names
    declare -a source_names

    # Extract names from the array
    for ((i=0; i<num_lines_source; i++)); do
        line=${source_array[i]}
        name=$(echo "$line" | awk '{print substr($0, 52, 33)}' | sed 's/ *$//')
        source_names[i]=$(echo "$name" | sed 's/^ *//; s/ *$//')
    done

    # Export source names to global variable
    export source_names
    export num_lines_source
}

function target_array_func() {
    local cxitool_output_target
    local IFS=$'\n'

    # Example command to get the output of cxitool for target (replace with actual command)
    cxitool_output_target=$(cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot ListKeys)

    # Parse the output into an array, skipping the first 3 lines (header)
    target_array=($(echo "$cxitool_output_target" | tail -n +4 | sed 's/[[:space:]]*$//'))

    # Check the number of lines in the target array
    num_lines_target=${#target_array[@]}

    # Declare an array to store target names
    declare -a target_names

    # Extract names from the array
    for ((i=0; i<num_lines_target; i++)); do
        line=${target_array[i]}
        name=$(echo "$line" | awk '{print substr($0, 52, 33)}' | sed 's/ *$//')
        target_names[i]=$(echo "$name" | sed 's/^ *//; s/ *$//')
    done

    # Export target names to global variable
    export target_names
    export num_lines_target
}

function compare_arrays_func() {
    # Compare the name fields and count matching names
    matched_count=0
    for ((i=0; i<num_lines_source; i++)); do
        for ((j=0; j<num_lines_target; j++)); do
            if [[ "${source_names[i]}" == "${target_names[j]}" ]]; then
                ((matched_count++))
                break
            fi
        done
    done

    # Log the total number of matching keys if there are any
    if (( matched_count > 0 )); then
        echo "WARNING: Found $matched_count matching keys between source and target HSMs."
    fi
}

# Time out duration for exiting
timeout_duration=10

# Menu
while true; do
    log "----------------------------------------------------------------------------------------"
    log "Choose function:"
    log "1. Encrypt PIN"
    log "2. Backup HSM"
    log "3. Restore HSM"
    log "4. Automatic backup all keys from HSM $sourceip to $targetip"
    log "5. Exit."
    log "6. Demo keys generation"
    
    read -t $timeout_duration -p "Choose (1-6): " choice
    
    if [ $? -eq 0 ]; then
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
            log "----------------------------------------------------------------------------------------"
	    log "Selected option: 4. Automatic backup all keys from HSM $sourceip to $targetip"
                backup_restore
                ;;
            5)
            log "----------------------------------------------------------------------------------------"
            log "Selected option: 5. -> Exit."
                exit 0
                ;;
            6)
            log "----------------------------------------------------------------------------------------"
            log "Selected option: 6. -> Demo key generation."
                demo_key_generation
                ;;
            *)
                log "Invalid selection. Please try again."
                ;;
        esac
    else
        log "No activity for $timeout_duration seconds. Exiting."
        exit 0
    fi
done
