#! /bin/bash

# snapshot branch
BRANCHES_ROOT_FOLDER=~/projs/Unsorted/dev_container/branches
# containers we won't shutdown and rename
declare -A IGNORED_CONTAINERS=([cnvim]=1 [deluge]=1 [plex]=1 [radarr]=1 [sonarr]=1 [jackett]=1 [nclient-nclient-1]=1 [backup_manager-backup_manager-1]=1)
# folders we will move to the branch folder
declare -a FOLDERS_TO_COPY=("/home/ism/projs/Unsorted/dev_container/vol_of_web" "/home/ism/projs/Unsorted/dev_container/vol_of_web2")
# compose path
COMPOSE_COMMAND_PATH=~/servers/media_server/docker-compose.yml

while test $# -gt 0
do
    case "$1" in
        --copy-files) COPY_FILES=true
            ;;
        --restore-files) RESTORE_FILES=true
            ;;
        --move-files) MOVE_FILES=true
            ;;
        --del-backup-files) DEL_BACKUP_FILES=true
            ;;
        --restore-files-from) RESTORE_FILES_FROM=true
            ;;
        --stop-save) STOP_AND_SAVE=true
            ;;
        --stop-save-delete) STOP_SAVE_DELETE=true
            ;;
        --restore) RESTORE=true
            ;;
        --restore-from) RESTORE_FROM=true
            ;;
        --del-images) DEL_IMAGES=true
            ;;
        --get-saved-services) GET_SAVED_SERVICES=true
            ;;
        --get-unsaved-services) GET_UNSAVED_SERVICES=true
            ;;
        --*) echo "bad option $1" && exit 1
            ;;
        *) WANTED_PATH=$1
            ;;
    esac
    shift
done

get_folder_name_from_branch () {
    local current_branch=$(git branch --show-current)
    local branch_folder_name="${current_branch////.}"
    echo $branch_folder_name
}

get_branch_folder_path () {
    local branch_folder_name=$(get_folder_name_from_branch)
    echo $branch_folder_path
    local branch_folder_path="${BRANCHES_ROOT_FOLDER}/${branch_folder_name}"
    echo $branch_folder_path
}

create_branch_folder () {
    mkdir -p $(get_branch_folder_path)
}

# snapshot containers
# read docker-name and id filter stuff stop container and save it
# Create the CSV Array Hash keyed by Col #2
get_all_containers_name_and_id () {
    declare -A containers_name_id_dict
    while IFS="," read -r cname cid
    do
        containers_name_id_dict[$cname]=$cid
    done <<EOD
$(docker container ls --format '{{.Names}},{{.ID}}')
EOD
    echo ${containers_name_id_dict[@]@K}
}

get_new_container_name () {
    echo "$(get_folder_name_from_branch).$1"
}

# stop container make an image out of it with the branch tag aas prefix and deletee the  original container 
stop_and_rename_containers () {
    declare -A containers_name_id_dict="($(get_all_containers_name_and_id))"
    for name in "${!containers_name_id_dict[@]}"; do
        if [[ ! ${IGNORED_CONTAINERS["$name"]} ]] ; then
            local new_tag_prefix=$(get_folder_name_from_branch)
            local current_tag=
            local current_image=
            local new_tag=${new_tag_prefix}.${current_tag}
            local new_name=$(get_new_container_name ${name})
            echo "stopping and renaming container '${name}' to '${new_name}'"
            local container_id=${containers_name_id_dict[$name]}
            echo "container id ${container_id}"
            docker stop $container_id
            docker rename $name $new_name
        fi
    done
}

stop_and_save_containers () {
    while IFS="," read -r cname cid image
    do
        if [[ ! ${IGNORED_CONTAINERS["$cname"]} ]] ; then
            IFS=":" read -r image_name image_tag <<< "$image"
            echo "${cname} ${cid} ${image}"
            if [[ -z $image_tag ]]; then
                image_tag=latest
            fi
            local new_image_tag=$(get_folder_name_from_branch).${image_tag}
            echo "commiting stopping and removing container ${cname} with image ${image} as ${image_name}:${new_image_tag}"
            docker stop $cid
            docker commit ${cid} ${image_name}:${new_image_tag}
            docker container rm ${cid}
            docker image rm ${image}
        fi
    done <<EOD
$(docker container ls --format '{{.Names}},{{.ID}},{{.Image}}')
EOD
}

restore_image_tags () {
    if [ -z $1 ] ; then
        local selected_branch_folder=$(get_folder_name_from_branch)
    else
        local selected_branch_folder=$1
    fi
    while IFS="," read -r image_name image_tag
    do
        if [[ $image_tag == ${selected_branch_folder}* ]]; then 
            local original_image_tag=${image_tag#"$(get_folder_name_from_branch)."}
            echo "changeing image ${image_name}:${image_tag} to ${image_name}:${original_image_tag}"
            docker image tag "${image_name}:${image_tag}" "${image_name}:${original_image_tag}"
        fi
    done <<EOD
$(docker images --format '{{ .Repository }},{{ .Tag }}')
EOD
}
# restore_image_tags
select_branch_folder () {
    echo $(ls $BRANCHES_ROOT_FOLDER | fzf)
}

get_all_containers_of_branch () {
    local selected_branch_folder=$1
    local wanted_branch="${selected_branch_folder//.//}"
    declare -A selected_branch_containers_name_id_dict
    while IFS="," read -r cname cid
    do
        selected_branch_containers_name_id_dict[$cname]=$cid
    done <<EOD
$(docker container ls -a -f "name=^${selected_branch_folder}." --format '{{.Names}},{{.ID}}')
EOD
echo ${selected_branch_containers_name_id_dict[@]@K}
}

rename_and_start_containers_of_branch () {
    if [ -z $1 ] ; then
        local selected_branch_folder=$(select_branch_folder)
    else
        local selected_branch_folder=$1
    fi
    declare -A selected_branch_containers_name_id_dict="($(get_all_containers_of_branch ${selected_branch_folder}))"
    for name in "${!selected_branch_containers_name_id_dict[@]}"; do
        local container_id=${selected_branch_containers_name_id_dict[$name]}
        local og_name=${name#"${selected_branch_folder}."}
        # mv its volumes back
        # echo "Moving volumes back"
        # docker inspect -f '{{ range .Mounts }}{{ if eq .Type "bind" }}{{ .Source }}{{ printf "\n" }}{{ end }}{{ end }}' $container_id | xargs -tp -I {} mv {} $CURRENT_BRANCH_FOLDER
        echo "renaming and starting container '${name}' to '${og_name}'"
        docker rename $name $og_name
        docker start $container_id
    done
}

copy_folders_to_branch_folder () {
    create_branch_folder
    for path in "${FOLDERS_TO_COPY[@]}"; do
        rsync -apv --relative ${path} $(get_branch_folder_path)
    done
}

delete_content_of_folders_to_copy () {
    for path in "${FOLDERS_TO_COPY[@]}"; do
        echo "rm -rf -I ${path}/*"
        rm -rf -I ${path}/*
    done
}

restore_folders_from_branch_folder () {
    if [ -z $1 ] ; then
        local branch_folder_path="${BRANCHES_ROOT_FOLDER}/$(select_branch_folder)"
    else
        local branch_folder_path=$1
    fi
    rsync -rv --relative "${branch_folder_path}/./" /
}

get_branch_saved_images_services () {
    if [ -z $1 ] ; then
        local selected_branch_folder=$(select_branch_folder)
    else
        local selected_branch_folder=$1
    fi
    while read -r image 
    do
        # find the corresponding setvice of the image
        local service=$(docker compose -f ${COMPOSE_COMMAND_PATH} config --format json | jq -r '.services | to_entries[] | "\(.key),\(.value.image)"' | grep ${image} | head -1 | awk -F ',' '{print $1}')
        local services+=(${service})
    done <<EOD
$(docker images --format '{{ .Repository }},{{ .Tag }}' | grep ${selected_branch_folder} | awk -F ',' '{print $1}')
EOD
    echo ${services[@]}
}

get_not_saved_services () {
    local saved_services=( $(get_branch_saved_images_services $(get_folder_name_from_branch)) )
    local all_services=( $(docker compose -f ${COMPOSE_COMMAND_PATH} config --format json | jq -r '.services | to_entries[] | .key' | tr '\n' ' ') )
    local diff=( $(echo ${all_services[@]} ${saved_services[@]} | tr ' ' '\n' | sort | uniq -u | tr '\n' ' ' ) )
    echo ${diff[@]}
}

del_branch_images () {
    if [ -z $1 ] ; then
        local selected_branch_folder=$(select_branch_folder)
    else
        local selected_branch_folder=$1
    fi

    while IFS="," read -r repo tag
    do
        docker rmi ${repo}:${tag}
    done <<EOD
$(docker images --format '{{ .Repository }},{{ .Tag }}' | grep ${selected_branch_folder})
EOD
}

del_branch_folder () {
    if [ -z $1 ] ; then
        local selected_branch_folder=$(select_branch_folder)
    else
        local selected_branch_folder=$1
    fi

    local branch_folder_path="${BRANCHES_ROOT_FOLDER}/${selected_branch_folder}"
    echo "rm -rf -I ${branch_folder_path}/*"
    rm -rf -I ${branch_folder_path}/*
}

main () {
    if [ $COPY_FILES ]; then
        del_branch_folder $(get_folder_name_from_branch)
        copy_folders_to_branch_folder
    fi

    if [ $RESTORE_FILES ]; then
        delete_content_of_folders_to_copy
        restore_folders_from_branch_folder $(get_branch_folder_path)
    fi

    if [ $MOVE_FILES ]; then
        del_branch_folder $(get_folder_name_from_branch)
        copy_folders_to_branch_folder
        delete_content_of_folders_to_copy
    fi

    if [ $RESTORE_FILES_FROM ]; then
        delete_content_of_folders_to_copy
        restore_folders_from_branch_folder
    fi

    if [ $STOP_AND_SAVE ]; then
        del_branch_images $(get_folder_name_from_branch)
        stop_and_save_containers
        del_branch_folder $(get_folder_name_from_branch)
        copy_folders_to_branch_folder
    fi

    if [ $STOP_SAVE_DELETE ]; then
        del_branch_images $(get_folder_name_from_branch)
        stop_and_save_containers
        del_branch_folder $(get_folder_name_from_branch)
        copy_folders_to_branch_folder
        delete_content_of_folders_to_copy
    fi

    if [ $RESTORE ]; then
        delete_content_of_folders_to_copy
        restore_folders_from_branch_folder $(get_branch_folder_path)
        # rename_and_start_containers_of_branch $(get_folder_name_from_branch)
        restore_image_tags
    fi

    if [ $RESTORE_FROM ]; then
        local branch_folder=$(select_branch_folder)
        local branch_folder_path="${BRANCHES_ROOT_FOLDER}/${branch_folder}"
        delete_content_of_folders_to_copy
        restore_folders_from_branch_folder $branch_folder_path
        # rename_and_start_containers_of_branch $branch_folder
        restore_image_tags ${branch_folder}
    fi

    if [ $GET_SAVED_SERVICES ]; then
        get_branch_saved_images_services $(get_folder_name_from_branch)
    fi

    if [ $GET_UNSAVED_SERVICES ]; then
        get_not_saved_services
    fi

    if [ $DEL_IMAGES ]; then
        del_branch_images $(get_folder_name_from_branch)
    fi

    if [ $DEL_BACKUP_FILES ]; then
        del_branch_folder $(get_folder_name_from_branch)
    fi
}

main

# print volumes (type: bind) per container
# docker ps -a --format '{{ .ID }}' | xargs -I {} docker inspect -f '{{ .Name }}{{ printf "\n" }}{{ range .Mounts }}{{ printf "\n\t" }}{{ .Type }} {{ if eq .Type "bind" }}{{ .Source }}{{ end }}{{ .Name }} => {{ .Destination }}{{ end }}{{ printf "\n" }}' {}

#docker inspect -f '{{ range .Mounts }}{{ if eq .Type "bind" }}{{ .Source }}{{ printf "\n" }}{{ end }}{{ end }}' plex


