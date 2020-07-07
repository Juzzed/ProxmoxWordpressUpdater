#!/usr/bin/env bash
###################################################################
# Script Name	    : Wordpress_updater                                                                                             
# Description	    : Updates Wordpress over proxmox to latest version                                                                                                                                                                                                
###################################################################

#const
VERSION="1.0"

#Req. variables
CONTAINER_ID=""

#Optional variables
TEMP_DIR="/tmp/wordpressTemp/"                                                          #Temp dir where the Wordpress zip will be donwloaded to
WORDPRESS_ZIP_NAME="WordpressLatest.zip"                                                #Wordpress.zip name
WORDPRESS_PATH="/usr/share/wordpress/"                                                  #Where wordpress is located on the container
WORDPRESS_BACKUP_PATH="/usr/share/wordpress_backup_"$(date +%m%d_%H%M%S)"/"             #Where production wordpress will be backuped to
WORDPRESS_TEMP_PATH="/usr/share/wordpress_temp_backup/"                                 #Where the wordpress.zip will be unziped
FOLDER_PERMISSIONS=755                                                                  #Permissions to set for the wordpress folders
FILE_PERMISSIONS=644                                                                    #Permissions to set for the wordpress files
WORDPRESS_DOWNLOAD_URL="https://de.wordpress.org/latest-de_DE.zip"

#Help
help_and_exit() {
  local retval=${1:-1}
  cat <<EOF
${0##*/} 
DESCRIPTION:
    This script will update/downgrade the Wordpress 
    version of the selected proxmox container

OPTIONS:
    -id [number], --containerid [number]        a natural number. This option
                                                has to be set
    -url [url], --downloadurl [url]             Worpress url to download from
    -zip [file], --zipname [file]               name of the downloaded file
    -p [dir], --wordpresspath [dir]             location of wordpress the directory
                                                on the proxmox container
    -b [dir], --wordpressbackuppath [dir]       location where the production wordpress
                                                backup goes
    -t [dir], --wordpresstemppath [dir]         location where the wordpress.zip will
                                                get unziped
    -tmp [dir], --tempdir [dir]                 temp dir where the Wordpress zip 
                                                will be donwloaded to
    -h, --help                                  this help
    -v, --version                               version of this script
EOF
  exit "$retval"
}

#loop through arguments
args=( )
while (( $# )); do
  case $1 in
    -id|--containerid)  CONTAINER_ID=$2 ;;
    -url|--downloadurl)  WORDPRESS_DOWNLOAD_URL=$2 ;;
    -zip|--zipname) WORDPRESS_ZIP_NAME=$2 ;;
    -p|--wordpresspath) WORDPRESS_PATH=$2 ;;
    -b|--wordpressbackuppath) WORDPRESS_BACKUP_PATH=$2 ;;
    -t|--wordpresstemppath) WORDPRESS_TEMP_PATH=$2 ;;
    -tmp|--tempdir) TEMP_DIR=$2 ;;
    -h|--help) help_and_exit 0 ;;
    -v|--version) echo $VERSION" "${0##*/}" (www.hostless.de)"
                exit 0;;
    -*)        printf 'Unknown option: %q\n\n' "$1"
               help_and_exit 1 ;;
    *)         args+=( "$1" ) ;;
  esac
  shift
done
set -- "${args[@]}"

#Debugging
echo "Outputing variables..."
echo "TEMP_DIR: "$TEMP_DIR
echo "WORDPRESS_ZIP_NAME: "$WORDPRESS_ZIP_NAME
echo "WORDPRESS_PATH: "$WORDPRESS_PATH
echo "WORDPRESS_BACKUP_PATH: "$WORDPRESS_BACKUP_PATH
echo "WORDPRESS_TEMP_PATH: "$WORDPRESS_TEMP_PATH
echo "FOLDER_PERMISSIONS: "$FOLDER_PERMISSIONS
echo "FILE_PERMISSIONS: "$FILE_PERMISSIONS
echo "CONTAINER_ID: "$CONTAINER_ID
echo ""

echo "Starting Wordpress Updater..."

if [ -z ${CONTAINER_ID+x} ]; 
    then 
        echo "Container ID is not set"
        exit;
    else 
        echo "Container ID $CONTAINER_ID will be updatet"
fi

echo ""

echo "Creating tmp directory ${TEMP_DIR}"
mkdir $TEMP_DIR
cd $TEMP_DIR

echo "Downloading wordpress"
wget -O $WORDPRESS_ZIP_NAME $WORDPRESS_DOWNLOAD_URL

echo "Installing unzip from repo.."
pct exec $CONTAINER_ID -- bash -c "apt-get install -y unzip"

echo "Backuping into ${WORDPRESS_BACKUP_PATH}"
pct exec $CONTAINER_ID -- bash -c "cp -r ${WORDPRESS_PATH} ${WORDPRESS_BACKUP_PATH}"
pct exec $CONTAINER_ID -- bash -c "mkdir ${WORDPRESS_TEMP_PATH}"

echo "Checking if ${WORDPRESS_BACKUP_PATH} exists"
PATH_EXISTS=`pct exec $CONTAINER_ID -- bash -c "[ -d ${WORDPRESS_BACKUP_PATH} ] && echo true || echo false"`
echo "Exists?: "$PATH_EXISTS
case $PATH_EXISTS in
"true")
    echo "Path ${WORDPRESS_BACKUP_PATH} exists"
    ;;
"false")
    echo "Path ${WORDPRESS_BACKUP_PATH} does not exist"
    echo "Exiting!"
    exit 0
    ;;
esac

echo "Removing old directories ${WORDPRESS_PATH}wp-includes and ${WORDPRESS_PATH}wp-admin"
pct exec $CONTAINER_ID -- bash -c "rm -r ${WORDPRESS_PATH}wp-includes ${WORDPRESS_PATH}wp-admin"

echo "Uploading to Container $CONTAINER_ID path ${WORDPRESS_TEMP_PATH}${WORDPRESS_ZIP_NAME}"
pct push $CONTAINER_ID $WORDPRESS_ZIP_NAME ${WORDPRESS_TEMP_PATH}${WORDPRESS_ZIP_NAME}

echo "Unzipping into ${WORDPRESS_TEMP_PATH}${WORDPRESS_ZIP_NAME}"
pct exec $CONTAINER_ID -- bash -c "unzip ${WORDPRESS_TEMP_PATH}${WORDPRESS_ZIP_NAME} -d ${WORDPRESS_TEMP_PATH}"

echo "Copying new files from ${WORDPRESS_TEMP_PATH}wordpress/ to ${WORDPRESS_PATH}"
pct exec $CONTAINER_ID -- bash -c "cp -r ${WORDPRESS_TEMP_PATH}wordpress/wp-includes ${WORDPRESS_PATH}"
pct exec $CONTAINER_ID -- bash -c "cp -r ${WORDPRESS_TEMP_PATH}wordpress/wp-admin ${WORDPRESS_PATH}"

echo "Copying newer updated files from ${WORDPRESS_TEMP_PATH}wordpress/wp-content to ${WORDPRESS_PATH}wp-content"
pct exec $CONTAINER_ID -- bash -c "yes | cp -rf ${WORDPRESS_TEMP_PATH}wordpress/wp-content ${WORDPRESS_PATH}wp-content"

echo "Copying newer updated root files from ${WORDPRESS_TEMP_PATH}wordpress/. to ${WORDPRESS_PATH}."
pct exec $CONTAINER_ID -- bash -c "yes | cp -rf ${WORDPRESS_TEMP_PATH}wordpress/. ${WORDPRESS_PATH}."

echo "Deleting ${WORDPRESS_TEMP_PATH}"
pct exec $CONTAINER_ID -- bash -c "rm -r ${WORDPRESS_TEMP_PATH}"

echo "Setting up permissions"
echo "Folders ${FOLDER_PERMISSIONS}"
pct exec $CONTAINER_ID -- bash -c "find ${WORDPRESS_PATH} -type d -exec chmod ${FOLDER_PERMISSIONS} {} \;"

echo "Files ${FILE_PERMISSIONS}"
pct exec $CONTAINER_ID -- bash -c "find ${WORDPRESS_PATH} -type f -exec chmod ${FILE_PERMISSIONS} {} \;"

echo "Changing owner and group to www-data"
pct exec $CONTAINER_ID -- bash -c "chown www-data:www-data -R ${WORDPRESS_PATH}"