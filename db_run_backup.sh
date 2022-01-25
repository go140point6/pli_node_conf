#!/bin/bash

# Authenticate sudo perms before script execution to avoid timeouts or errors
sudo -l > /dev/null 2>&1

# Set Colour Vars
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get current user id and store as var
USER_ID=$(getent passwd $EUID | cut -d: -f1)
GROUP_ID=$(getent group $EUID | cut -d: -f1)

source ~/"plinode_$(hostname -f)".vars


FUNC_DB_VARS(){
## VARIABLE / PARAMETER DEFINITIONS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


    PLI_DB_VARS_FILE="plinode_$(hostname -f)"_sql.vars
    if [ ! -e ~/$PLI_DB_VARS_FILE ]; then
        clear
        echo
        echo
        echo -e "${RED} #### ERROR: No VARIABLES file found. ####${NC}"
        echo
        echo -e "${RED} ..creating local vars file '$HOME/$PLI_DB_VARS_FILE' ${NC}"
        cp -n sample_sql.vars ~/$PLI_DB_VARS_FILE
        chmod 600 ~/$PLI_DB_VARS_FILE
        echo
        echo -e "${GREEN} please update the vars file with your specific values.. ${NC}"
        echo -e "${GREEN} copy command to edit: ${NC}"
        echo
        echo -e "${GREEN}       nano ~/"$PLI_VARS_FILE" ${NC}"
        echo
        echo
        #sleep 2s
        exit 1
    fi
    source ~/$PLI_DB_VARS_FILE
}



FUNC_CHECK_DIRS(){

# checks that the DB_BACKUP_ROOT var is not NULL & not 'root' or is not NULL & not $HOME so as not to create these folder & change perms
if ([ ! -z "$DB_BACKUP_ROOT" ] && [ "$DB_BACKUP_ROOT" != "root" ]) || ([ ! -z "$DB_BACKUP_ROOT" ] && [ "$DB_BACKUP_ROOT" != "$HOME" ]); then
    echo "variable 'DB_BACKUP_ROOT' value is: $DB_BACKUP_ROOT"
    echo "variable 'DB_BACKUP_ROOT' is not NULL"
    echo "making the directory..."
    if [ ! -d "/$DB_BACKUP_ROOT" ]; then
        sudo mkdir "/$DB_BACKUP_ROOT"
        sudo chown $USER_ID\:$DB_BACKUP_GUSER -R "/$DB_BACKUP_ROOT";
    fi
else
    # if NULL then defaults to using $HOME & updates the 'DB_BACKUP_PATH'variable
    if [ -z "$DB_BACKUP_ROOT" ]; then
        DB_BACKUP_ROOT="$HOME"
        echo "..Detected NULL we set the variable to: "$HOME""
        echo "..updating the 'DB_BACKUP_PATH' variable.."
        DB_BACKUP_PATH="$DB_BACKUP_ROOT/$DB_BACKUP_DIR"

        # adds the variable value to the VARS file
        echo "..updating file "$PLI_DB_VARS_FILE" variable DB_BACKUP_ROOT to: \$HOME"
        sed -i.bak 's/DB_BACKUP_ROOT=\"\"/DB_BACKUP_ROOT=\"\$HOME\"/g' ~/$PLI_DB_VARS_FILE
    fi
    echo "var is set to "$DB_BACKUP_ROOT""
    echo ".... nothing else to do.. continuing to next variable";
fi


# Checks if NOT NULL for the 'DB_BACKUP_DIR'variable
if [ ! -z "$DB_BACKUP_DIR" ] ; then
    echo "the variable DB_BACKUP_DIR value is: $DB_BACKUP_DIR"
    echo "var is not NULL"
    echo "lets make the directory"
    # Checks if directory exists & creates if not + sets perms
    if [ ! -d "/$DB_BACKUP_ROOT/$DB_BACKUP_DIR" ]; then
        sudo mkdir "/$DB_BACKUP_ROOT/$DB_BACKUP_DIR"
        sudo chown $USER_ID\:$DB_BACKUP_GUSER -R "/$DB_BACKUP_ROOT/$DB_BACKUP_DIR"
        sudo chmod g+w -R "/$DB_BACKUP_ROOT/$DB_BACKUP_DIR";
    fi
else
    # If NULL then defaults to using 'node_backups' for 'DB_BACKUP_DIR'variable
    echo "the variable DB_BACKUP_DIR value is: $DB_BACKUP_DIR"
    echo "Detected NULL - we set the value"
    DB_BACKUP_DIR="node_backups"

    # adds the variable value to the VARS file
    echo "..updating file "$PLI_DB_VARS_FILE" variable DB_BACKUP_DIR to: "$DB_BACKUP_DIR""
    sed -i.bak 's/DB_BACKUP_DIR=\"\"/DB_BACKUP_DIR=\"'$DB_BACKUP_DIR'\"/g' ~/$PLI_DB_VARS_FILE

    # Checks if directory exists & creates if not + sets perms
    sudo mkdir "/$DB_BACKUP_ROOT/$DB_BACKUP_DIR"
    sudo chown $USER_ID\:$DB_BACKUP_GUSER -R "/$DB_BACKUP_ROOT/$DB_BACKUP_DIR"
    sudo chmod g+w -R "/$DB_BACKUP_ROOT/$DB_BACKUP_DIR";
    
    # Updates the 'DB_BACKUP_PATH'variable
    DB_BACKUP_PATH="$DB_BACKUP_ROOT/$DB_BACKUP_DIR"

    #cat ~/$PLI_DB_VARS_FILE | grep $DB_BACKUP_DIR
    echo "exiting directory check & continuing...";
    sleep 2s
fi

echo "your configured node backup PATH is: $DB_BACKUP_PATH"
sleep 2s

}



FUNC_DB_PRE_CHECKS(){
# check that necessary user / groups are in place 

USER_ID=$(getent passwd $EUID | cut -d: -f1)


#USER_ID=$(getent passwd $EUID | cut -d: -f1)
#GROUP_ID=$(getent group $EUID | cut -d: -f1)


#check DB_BACKUP_FUSER  values
if [ -z "$DB_BACKUP_FUSER" ]; then
    export DB_BACKUP_FUSER="$USER_ID"
    echo "..Detected NULL for 'DB_BACKUP_FUSER' - we set the variable to: "$USER_ID""

    # adds the variable value to the VARS file
    echo "..updating file "$PLI_DB_VARS_FILE" variable 'DB_BACKUP_FUSER' to: $USER_ID"
    sed -i.bak 's/DB_BACKUP_FUSER=\"\"/DB_BACKUP_FUSER=\"\$USER_ID\"/g' ~/$PLI_DB_VARS_FILE
fi

# check shared group '$DB_BACKUP_GUSER' exists & set permissions
if [ -z "$DB_BACKUP_GUSER" ] && [ ! $(getent group nodebackup) ]; then
    echo "variable 'DB_BACKUP_GUSER is: NULL && 'default' does not exist"
    echo "creating group 'nodebackup'"
    sudo groupadd nodebackup

    # adds the variable value to the VARS file
    echo "..updating file "$PLI_DB_VARS_FILE" variable DB_BACKUP_GUSER to: nodebackup"
    sed -i.bak 's/DB_BACKUP_GUSER=\"\"/DB_BACKUP_GUSER=\"nodebackup\"/g' ~/$PLI_DB_VARS_FILE
    export DB_BACKUP_GUSER="nodebackup"

elif [ ! -z "$DB_BACKUP_GUSER" ] && [ ! $(getent group $DB_BACKUP_GUSER) ]; then
    echo "variable 'DB_BACKUP_GUSER is: NOT NULL && does not exist"
    echo "creating group "
    sudo groupadd $DB_BACKUP_GUSER
fi



# add users to the group
if [ ! -z "$GD_FUSER" ]; then
    DB_GUSER_MEMBER=(postgres $USER_ID $GD_FUSER)
    echo "${DB_GUSER_MEMBER[@]}"
else
    DB_GUSER_MEMBER=(postgres $USER_ID)
    echo "${DB_GUSER_MEMBER[@]}"
fi

for _user in "${DB_GUSER_MEMBER[@]}"
do
    hash $_user &> /dev/null
    echo "...adding user "$_user" to group "$DB_BACKUP_GUSER""
    sudo usermod -aG "$DB_BACKUP_GUSER" "$_user"
done 


# ensure that current user is member of postgres group
#if ! id -nG $USER_ID | grep -qw postgres; then
#    echo $USER_ID does not belong to group: postgres
#    sudo usermod -aG postgres $USER_ID
#fi


# ensure that user 'postgres' is member of $DB_BACKUP_GUSER group
#if ! id -nG postgres | grep -qw "$DB_BACKUP_GUSER"; then
#    echo postgres does not belong to $DB_BACKUP_GUSER
#    sudo usermod -aG $DB_BACKUP_GUSER postgres
#fi

}





FUNC_DB_BACKUP_LOCAL(){

FUNC_DB_PRE_CHECKS;
FUNC_CHECK_DIRS;

# checks if the '.pgpass' credentials file exists - if not creates in home folder & copies to dest folder
# & sets perms
if [ ! -e /$DB_BACKUP_PATH/.pgpass ]; then
    #clear
cat <<EOF >> ~/.pgpass
Localhost:5432:$DB_NAME:postgres:$DB_PWD_NEW
EOF
    chmod 600 ~/.pgpass
    cp -n ~/.pgpass /$DB_BACKUP_PATH/.pgpass
    sudo chown postgres:postgres /$DB_BACKUP_PATH/.pgpass
fi

# switch to 'postgres' user and run command to create inital sql dump file
sudo su postgres -c "export PGPASSFILE="/$DB_BACKUP_PATH/.pgpass"; pg_dump -c -w -U postgres $DB_NAME | gzip > /$DB_BACKUP_OBJ"
error_exit;
sudo chown $DB_BACKUP_FUSER:$DB_BACKUP_GUSER /$DB_BACKUP_OBJ
sleep 2s
FUNC_DB_BACKUP_ENC;
}



FUNC_DB_BACKUP_ENC(){
# runs GnuPG or gpg to encrypt the sql dump file - uses main keystore password as secret
# outputs file to new folder ready for upload
sudo gpg --yes --batch --passphrase=$PASS_KEYSTORE -o /$ENC_PATH/$ENC_FNAME -c /$DB_BACKUP_OBJ
error_exit;
sudo chown $DB_BACKUP_FUSER:$DB_BACKUP_GUSER /$ENC_PATH/$ENC_FNAME
rm -f /$DB_BACKUP_OBJ
}



FUNC_DB_BACKUP_REMOTE(){
# add check that gupload is installed!
# switches to gupload user to run cmd to upload encrypted file to your google drive - skips existing files
sudo su gdbackup -c "cd ~/; .google-drive-upload/bin/gupload -q -d /$DB_BACKUP_PATH/*.gpg -C $(hostname -f) --hide"
error_exit;
}

#FUNC_CLEAN_UP_REMOTE(){
# remove files store in the backups folder    
#}



error_exit()
{
    if [ $? != 0 ]; then
        echo "ERROR"
        exit 1
    else
        return
    fi
}



FUNC_DB_VARS;
#FUNC_DB_BACKUP_LOCAL;
#FUNC_DB_BACKUP_REMOTE;


clear
case "$1" in
        local)
                FUNC_DB_BACKUP_LOCAL
                ;;
        remote)
                FUNC_DB_BACKUP_REMOTE
                ;;
        -p)
                FUNC_DB_PRE_CHECKS
                ;;
        -f)
                FUNC_CHECK_DIRS
                ;;
        *)
                

                echo 
                echo 
                echo "Usage: $0 {function}"
                echo 
                echo "where {function} is one of the following;"
                echo 
                echo "      local      ==  performs a local DB backup only "
                echo "      remote     ==  copies local DB backup to google drive (if enabled)"
                echo
                echo "      -p         ==  carries out pre-checks on user / group variables defined in file: $PLI_DB_VARS_FILE "
                echo
                echo "      -f         ==  carries out pre-checks on directory / path variables defined in file: $PLI_DB_VARS_FILE "
esac
