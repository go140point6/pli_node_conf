#!/bin/bash

# Get current user id and store as var
USER_ID=$(getent passwd $EUID | cut -d: -f1)

# Authenticate sudo perms before script execution to avoid timeouts or errors
sudo -l > /dev/null 2>&1


# Set Colour Vars
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

source ~/"plinode_$(hostname -f)".vars
source ~/"plinode_$(hostname -f)"_bkup.vars



FUNC_RESTORE_DECRYPT(){
    
    PLI_VARS_FILE="plinode_$(hostname -f)".vars
    #echo $PLI_VARS_FILE
    if [[ ! -e ~/$PLI_VARS_FILE ]]; then
        read -r -p "please enter the previous systems .env.password key : " PASS_KEYSTORE      
    fi


    #BACKUP_FILE="$IFS"
    RESTORE_FILE=""
    #echo "Starting value of 'Restore File' var: $RESTORE_FILE"
    RESTORE_FILE=$(echo $BACKUP_FILE | sed 's/\.[^.]*$//')
    #echo "Return new value of 'Restore File' var: $RESTORE_FILE"
    #echo "key store secret used: $PASS_KEYSTORE"
    #echo 
    #echo 
    #echo $(ls -lh  /plinode_backups/)
    #echo 
    #echo 
    gpg --verbose --batch --passphrase=$PASS_KEYSTORE -o $RESTORE_FILE --decrypt $BACKUP_FILE  > /dev/null 2>&1 

    #echo 
    #echo 
    #echo $(ls -lh  /plinode_backups/)
    #echo 
    #echo 
    if [[ "$BACKUP_FILE" =~ "plugin_mainnet_db" ]]; then
        #echo "matched 'contains' db name..."
        FUNC_RESTORE_DB
    elif [[ "$BACKUP_FILE" =~ "conf_vars" ]]; then
        #echo "else returned so must be file restore..."
        FUNC_RESTORE_CONF
    fi


    sudo chown $USER_ID\:$DB_BACKUP_GUSER -R "/$DB_BACKUP_DIR"
    #sudo chmod g+rw "/$DB_BACKUP_DIR";

    #echo "if complete. existing..."
    if [[ ! -e "$RESTORE_FILE" ]]; then
    echo "DECRYPT ERROR :: Restore file does not exist"
    FUNC_EXIT_ERROR;
    fi

    FUNC_EXIT;

}

FUNC_RESTORE_DB(){

    ### removes last extension suffix to get next file name
    RESTORE_FILE_SQL=$(echo "$RESTORE_FILE" | sed -e 's/\.[^.]*$//')
    
    sudo chown $USER_ID\:$DB_BACKUP_GUSER -R "/$DB_BACKUP_DIR"


    if [[ ! -e "$RESTORE_FILE" ]]; then
    echo "ERROR :: Restore file does not exist"
    FUNC_EXIT_ERROR;
    fi

    echo "   DB RESTORE.... unzip file name: $RESTORE_FILE"
    #echo " the path to file is: $DB_BACKUP_PATH"
    #echo 
    gunzip -vdf $RESTORE_FILE > /dev/null 2>&1
    sudo chown $USER_ID\:$DB_BACKUP_GUSER -R "$RESTORE_FILE_SQL"
    sleep 2


    echo "   DB RESTORE.... psql file name: $RESTORE_FILE_SQL"
    sudo su postgres -c "export PGPASSFILE="$DB_BACKUP_PATH/.pgpass"; psql -d $DB_NAME < $RESTORE_FILE_SQL" > /dev/null 2>&1
    sleep 2
    
    echo "   DB RESTORE.... restarting service postgresql"
    sudo systemctl restart postgresql
    sleep 15

    ### NOTE: .pgpass file would need to be manually re-created inorder to restore files? As would the .env.password keystore

    #sudo chown $USER_ID\:$DB_BACKUP_GUSER $DB_BACKUP_PATH/\*.sql
    shred -uz -n 1 $RESTORE_FILE_SQL > /dev/null 2>&1
    
    echo "  DB RESTORE COMPLETED"

    if [[ "$DR_RESTORE" == "true" ]]; then
        FUNC_REBUILD_EI
    fi

    FUNC_EXIT
}


FUNC_RESTORE_CONF(){

    RESTORE_FILE_CONF=$(echo "$RESTORE_FILE" | sed -e 's/\.[^.]*$//')
    echo "   CONFIG FILES RESTORE...."

    echo "uncompressing gz file: $RESTORE_FILE"
    gunzip -df $RESTORE_FILE
    sleep 2

    echo "unpacking tar file: $RESTORE_FILE_CONF"
    tar -xvf $RESTORE_FILE_CONF --directory=/
    sleep 2

    shred -uz -n 1 $RESTORE_FILE $RESTORE_FILE_CONF > /dev/null 2>&1
    FUNC_EXIT
}


FUNC_REBUILD_EI(){


    source ~/"plinode_$(hostname -f)".vars

    EI_FILE=$(echo "$BASH_FILE3" | sed -e 's/\.[^.]*$//')                       # cuts the file extension to get the namespace for pm2
    pm2 stop $EI_FILE && pm2 delete $EI_FILE && pm2 reset all && pm2 save       # deletes existing EI process 
    sleep 3s

    #echo $PWD
    echo "DB RESTORE - REBUILD EI - authenticate to API with credentials file: $FILE_API"
    plugin admin login -f ~/plugin-deployment/$FILE_API

    echo "DB RESTORE - REBUILD EI - delete existing EI"
    plugin initiators destroy $PLI_L_INIT_NAME
    sleep 2s
    cd /$PLI_DEPLOY_PATH/$PLI_INITOR_DIR

    echo "DB RESTORE - REBUILD EI - generating new EI values & extract to file"
    plugin initiators create $PLI_L_INIT_NAME http://localhost:8080/jobs > $PLI_INIT_RAWFILE

    sed -i 's/ ║ /,/g;s/╬//g;s/═//g;s/║//g' $PLI_INIT_RAWFILE
    sed -n '/'"$PLI_L_INIT_NAME"'/,//p' $PLI_INIT_RAWFILE > $PLI_INIT_DATFILE
    sed -i 's/,/\n/g;s/^.'"$PLI_L_INIT_NAME"'//g' $PLI_INIT_DATFILE
    sed -i 's/^http.*//g' $PLI_INIT_DATFILE
    sed -i.bak '/^$/d;/^\s*$/d;s/[ \t]\+$//' $PLI_INIT_DATFILE
    cp $PLI_INIT_DATFILE ~/$PLI_INIT_DATFILE.bak  && chmod 600 ~/$PLI_INIT_DATFILE.bak

    #cat $PLI_INIT_DATFILE
    sleep 2s

    echo "DB RESTORE - REBUILD EI - reading new EI values to variables"
    read -r -d '' EXT_ACCESSKEY EXT_SECRET EXT_OUTGOINGTOKEN EXT_OUTGOINGSECRET <$PLI_INIT_DATFILE


    echo "DB RESTORE - REBUILD EI - creating new EI file"
    cd /$PLI_DEPLOY_PATH
    cat <<EOF > $BASH_FILE3
#!/bin/bash
export EI_DATABASEURL=postgresql://postgres:${DB_PWD_NEW}@127.0.0.1:5432/plugin_mainnet_db?sslmode=disable
export EI_CHAINLINKURL=http://localhost:6688
export EI_IC_ACCESSKEY=${EXT_ACCESSKEY}
export EI_IC_SECRET=${EXT_SECRET}
export EI_CI_ACCESSKEY=${EXT_OUTGOINGTOKEN}
export EI_CI_SECRET=${EXT_OUTGOINGSECRET}
echo *** Starting EXTERNAL INITIATOR ***
external-initiator "{\"name\":\"$PLI_E_INIT_NAME\",\"type\":\"xinfin\",\"url\":\"https://plirpc.blocksscan.io\"}" --chainlinkurl "http://localhost:6688/"
EOF
    #sleep 1s
    #cat $BASH_FILE3
    chmod u+x $BASH_FILE3

    pm2 start $BASH_FILE3
    pm2 save

}


FUNC_EXIT(){
	exit 0
	}


FUNC_EXIT_ERROR(){
	exit 1
}
  



FUNC_RESTORE_MENU(){


    node_backup_arr=()
    BACKUP_FILE=$'\n' read -r -d '' -a node_backup_arr < <( find /plinode_backups/ -type f -name *.gpg | head -n 8 | sort )
    #node_backup_arr+=(quit)
    #echo ${node_backup_arr[@]}
    node_backup_arr_len=${#node_backup_arr[@]}
    #echo $node_backup_arr_len

    echo
    echo "          Showing last 8 backup files. "
    echo "          Select the number for the file you wish to restore "
    echo

    select _file in "${node_backup_arr[@]}" "QUIT"
    do
        case $_file in
            ${node_backup_arr[0]}) echo "Restoring file: ${node_backup_arr[0]}" ; BACKUP_FILE="${node_backup_arr[0]}"; FUNC_RESTORE_DECRYPT; break ;;
            ${node_backup_arr[1]}) echo "Restoring file: ${node_backup_arr[1]}" ; BACKUP_FILE="${node_backup_arr[1]}"; FUNC_RESTORE_DECRYPT; break ;;
            ${node_backup_arr[2]}) echo "Restoring file: ${node_backup_arr[2]}" ; BACKUP_FILE="${node_backup_arr[2]}"; FUNC_RESTORE_DECRYPT; break ;;
            ${node_backup_arr[3]}) echo "Restoring file: ${node_backup_arr[3]}" ; BACKUP_FILE="${node_backup_arr[3]}"; FUNC_RESTORE_DECRYPT; break ;;
            ${node_backup_arr[4]}) echo "Restoring file: ${node_backup_arr[4]}" ; BACKUP_FILE="${node_backup_arr[4]}"; FUNC_RESTORE_DECRYPT; break ;;
            ${node_backup_arr[5]}) echo "Restoring file: ${node_backup_arr[5]}" ; BACKUP_FILE="${node_backup_arr[5]}"; FUNC_RESTORE_DECRYPT; break ;;
            ${node_backup_arr[6]}) echo "Restoring file: ${node_backup_arr[6]}" ; BACKUP_FILE="${node_backup_arr[6]}"; FUNC_RESTORE_DECRYPT; break ;;
            ${node_backup_arr[7]}) echo "Restoring file: ${node_backup_arr[7]}" ; BACKUP_FILE="${node_backup_arr[7]}"; FUNC_RESTORE_DECRYPT; break ;;
            "QUIT") echo "exiting now..." ; FUNC_EXIT; break ;;
            *) echo invalid option;;
        esac
    done

}



echo -e "${GREEN}#########################################################################${NC}"
echo -e "${GREEN}#########################################################################${NC}"
echo -e "${GREEN}##${NC}"
echo -e "${GREEN}##      RESTORE SCENARIO CONFIRMATION...${NC}"
echo -e "${GREEN}##${NC}"

# Ask the user acc for login details (comment out to disable)
DR_RESTORE=false
    while true; do
        echo -e "${GREEN}##${NC}"
        echo -e "${GREEN}##  A Full Restore is ONLY where you have moved backup files to a FRESH / NEW VPS host${NC}"
        echo -e "${GREEN}##  this includes where you have reset your previous VPS installation to start again..${NC}"
        echo -e "${GREEN}##${NC}"
        echo
        read -t15 -r -p "Are you performing a Full Restore to BLANK / NEW VPS ? (Y/n) " _RES_INPUT
        if [ $? -gt 128 ]; then
            #clear
            echo
            echo
            echo "....timed out waiting for user response - proceeding as standard in-place restore to existing system..."
            echo
            #DR_RESTORE=false
            FUNC_RESTORE_MENU;
        fi
        case $_RES_INPUT in
            [Yy][Ee][Ss]|[Yy]* ) 
                DR_RESTORE=true
                FUNC_RESTORE_MENU
                break
                ;;
            [Nn][Oo]|[Nn]* ) 
                FUNC_RESTORE_MENU
                ;;
            * ) echo "Please answer (y)es or (n)o.";;
        esac
    done