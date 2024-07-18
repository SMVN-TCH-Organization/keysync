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

VERSION="1.0.0"

# Declare variables as a global variable
sourceslot=""
keyname=""
targetslot=""
sourceip=""
targetip=""

# Set logfile name with date
logfile="hsm_operations_$(date '+%Y-%m-%d').log"

# Function to log messages with timestamp and username
function log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [User: $USER] $1" | tee -a $logfile
}

# Check if config.properties file exists
if [ -f "config.properties" ]; then
    # Read values from config.properties file
    sourceip=$(sed -n '1p' config.properties)
    sourceslot=$(sed -n '2p' config.properties)
    targetip=$(sed -n '3p' config.properties)
    targetslot=$(sed -n '4p' config.properties)
    log "Values loaded from config.properties:"
    log "Source HSM IP: $sourceip"
    log "Source SLOT: $sourceslot"
    log "Target HSM IP: $targetip"
    log "Target SLOT: $targetslot"
else
    # Prompt user for input and save to config.properties
    log "No information about source and target HSM was found"
    log "Enter the IP address of the source HSM"
    read sourceip
    log "Enter the source SLOT number"
    read sourceslot
    log "Enter the IP address of the target HSM"
    read targetip
    log "Enter the target SLOT number"
    read targetslot

    # Save the input to config.properties
    echo "$sourceip" > config.properties
    echo "$sourceslot" >> config.properties
    echo "$targetip" >> config.properties
    echo "$targetslot" >> config.properties

    log "Values saved to config.properties:"
    log "Source HSM IP: $sourceip"
    log "Source SLOT: $sourceslot"
    log "Target HSM IP: $targetip"
    log "Target SLOT: $targetslot"
fi


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
        cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot ListKeys | tee -a $logfile
        
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
        ls -alh *.kbk
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
                cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot Restorekey=$file
                log "$((restored_keys+1)) key(s) out of $total_keys have been restored to HSM $targetip"
                ((restored_keys++))
            done
        else
            # Perform restore for 1 file
            cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot Restorekey=$keyfile
            log "1 key has been restored to HSM $targetip"
        fi

        log "Listing keys from target HSM $targetip"
        cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot ListKeys
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
        cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot ListKeys

        log "Backing up all keys to the current directory..."
        cxitool Dev=$sourceip LogonPass=USR_0000,$pin Group=$sourceslot Name=* OutDir=~ backupkey

        # Restore all keys
        log "Listing backup key files in the current directory"
        log "----------------------------------------------------------------------------------------"
        ls -alh *.kbk
        log "----------------------------------------------------------------------------------------"

        log "Restoring all keys to HSM $targetip"
        restored_keys=0
        for file in *.kbk; do
            cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot Restorekey=$file
            log "$((restored_keys+1)) key(s) out of $(ls -1 *.kbk | wc -l) have been restored to HSM $targetip"
            ((restored_keys++))
        done
        
        log "Listing keys from source HSM $targetip"
        cxitool Dev=$targetip LogonPass=USR_0000,$pin Group=$targetslot ListKeys
        pin=""
    else
        log "File encrypted_data.txt not found. Please repeat option 1. Encrypt PIN"
    fi
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
            encrypt_text
            ;;
        2)
            backup_hsm
            ;;
        3)
            restore_hsm
            ;;
        4)
            backup_restore
            ;;
        5)
            log "Exit."
            exit 0
            ;;
        *)
            log "Invalid selection. Please try again."
            ;;
    esac
done
