#!/bin/bash

source `pwd`/main.ini
#
# A script to build static library for Android
#

build_arches=""
build_mode=""
build_library=""
build_api=""
build_gcc_version=""
build_platform=""
build_list_all_libraries=no
build_show_help_message=no

function contains() {
    local n=$#
    local value=${!n}
    for ((i=1;i < $#;i++)) {
            if [ "${!i}" == "${value}" ]; then
                echo "y"
                return 0
            fi
        }
        echo "n"
        return 1
}

function usage()
{
    echo "You should follow the instructions here to build static library for $cfg_platform_name"
    echo ""
    echo "./build_png.sh"
    echo "\t[-h --help]  "
    echo "\t--libs=[all | png,lua,tiff,jpeg,webp,zlib etc]"
    echo "\t[--arch | -a]=[all | $cfg_help_arch_string etc]"
    echo "\t[--mode | -m]=[release | debug]"
    echo "\t[--list | -l]"
    echo ""
    echo "Sample:"
    echo "$cfg_help_sample_string"
    echo ""
}



while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        --help | -h)
            build_show_help_message=yes
            ;;
        --platform | -p)
            build_platform=$VALUE
            ;;
        --libs)
            build_library=$VALUE
            ;;
        --arch | -a)
            build_arches=$VALUE
            ;;
        --mode | -m)
            build_mode=$VALUE
            ;;
        --list | -l)
            build_list_all_libraries=yes
            ;;
        --api)
            build_api=$VALUE
            ;;
        --gcc)
            build_gcc_version=$VALUE
            ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
            exit 1
            ;;
    esac
    shift
done

#check invalid platform
function check_invalid_platform()
{
    # echo "checking ${build_platform} is in ${cfg_all_valid_platforms[@]}"
    if [ $(contains "${cfg_all_valid_platforms[@]}" $build_platform) == "n" ]; then
        echo "Invalid platform! Only ${cfg_all_valid_platforms[@]} is acceptable."
        exit 1
    fi
}

check_invalid_platform

##load platform config files
for p in ${cfg_all_valid_platforms[@]}
do
    if [ $(contains "${cfg_all_valid_platforms[@]}" $build_platform) == "y" ];then
        platform_config_file=${build_platform}.ini
        if [ ! -f $platform_config_file ];then
            echo "platform config file is not exists!"
            exit;
        fi
        source $platform_config_file
        [[ -z "${build_api}" ]] && build_api=$cfg_default_build_api
        [[ -z "${build_gcc_version}" ]] && build_gcc_version=$cfg_default_gcc_version
    fi
done



function list_all_supported_libraries()
{

    echo "Supported libraries and versions:"
    echo "\t"

    for lib in ${cfg_all_supported_libraries[@]}
    do
        all_supported_libraries=$(find  ../contrib/src -type f | grep SHA512SUMS | xargs cat | awk 'match ($0, /.tgz|.tar.gz|.zip|.tar.xz/) { print substr($2,0,length($2)-RLENGTH)}' | grep $lib | awk '{print $1}')
        echo $all_supported_libraries | awk '{ print $1}'
    done
}

if [ $build_list_all_libraries = "yes" ];then
    list_all_supported_libraries
    exit 1
fi

if [ $build_show_help_message = "yes" ];then
    usage
    exit 1
fi


if test -z "$build_arches"
then
    build_arches=$cfg_default_build_arches
fi

if test -z "$build_library"
then
    while true; do
        read -p "Do you wish to build with all the libraries?[yes|no]" yn
        case $yn in
            [Yy]* ) build_library=$cfg_default_build_libraries; break;;
            [Nn]* ) usage;exit;;
            * ) echo "Please answer yes or no.";;
        esac
    done
fi

if test -z "$build_mode"
then
    echo "You don't specify a valid build mode, use release mode"
    build_mode=$cfg_default_build_mode
fi


if [ $cfg_platform_name = "Android" ];then
    echo "build api is $build_api."
    if [[ ! $build_api =~ ^[0-9]+$ ]]; then
        echo "Android API should be integers!"
        usage
        exit 1
    fi

    if [[ ! $build_gcc_version =~ ^[0-9]\.[0-9]+$ ]]; then
        echo "Invalid gcc version number! Gcc version should be numerical numbers."
        usage
        exit 1
    fi 

    if [ ! -z $cfg_android_ndk_path ];then
        export ANDROID_NDK=$cfg_android_ndk_path
    fi
    
fi

current_dir=`pwd`
top_dir=$current_dir/..

all_arches=(${cfg_all_supported_arches[@]})
all_libraries=(${cfg_all_supported_libraries[@]})

if [ $build_arches = $cfg_default_build_arches ]; then
    build_arches=(${cfg_default_arches_all[@]})
else
    build_arches=(${build_arches//,/ })
fi

if [ $build_library = $cfg_default_build_libraries ]; then
    build_library=(${cfg_default_libraries_all[@]})
else
    build_library=(${build_library//,/ })
fi

#check invalid arch type
function check_invalid_arch_type()
{
    for arch in ${build_arches[@]}
    do
        echo "checking ${arch} is in ${all_arches[@]}"
        if [ $(contains "${all_arches[@]}" $arch) == "n" ]; then
            echo "Invalid arch! Only ${all_arches[@]} is acceptable."
            exit 1
        fi
    done
}

check_invalid_arch_type

#check invalid library name
function check_invalid_library_name()
{
    for lib in "${build_library[@]}"
    do
        echo "checking ${lib} is in ${all_libraries[@]}"
        if [ $(contains "${all_libraries[@]}" $lib) == "n" ]; then
            echo "Invalid library names! Only ${all_libraries[@]} is acceptable!"
            exit 1
        fi
    done
}

check_invalid_library_name


#check invalid build mode, only debug and release is acceptable
function check_invalid_build_mode() {
    if [ $(contains ${cfg_valid_build_mode[@]} $1) == "n" ];then
        echo "invalid build mode, only: ${cfg_valid_build_mode[@]} is allowed!"
        usage
        exit 1
    fi
}

check_invalid_build_mode $build_mode


function create_fat_library()
{
    library_name=$1
    #strip & create fat library
    LIPO="xcrun -sdk iphoneos lipo"
    STRIP="xcrun -sdk iphoneos strip"

    if [ -f $cfg_platform_name/$library_name/prebuilt/lib$library_name.a ]; then
        echo "removing old fat library..."
        rm $cfg_platform_name/$library_name/prebuilt/lib$library_name.a
    fi

    all_static_libs=$(find $cfg_platform_name/$library_name/prebuilt -type f -name "lib$library_name.a")

    echo "create fat library lib$library_name for $all_static_libs"
    $LIPO -create  $all_static_libs \
          -output $cfg_platform_name/$library_name/prebuilt/lib$library_name.a

    # rm $all_static_libs

    # remove debugging info don't strip
    # $STRIP -S $library_name/prebuilt/lib$library_name.a
    $LIPO -info $cfg_platform_name/$library_name/prebuilt/lib$library_name.a
}


function set_build_mode_cflags()
{
    build_flag=cfg_build_${build_mode}_mode
    OPTIM=${!build_flag}

    export OPTIM
}



# build all the libraries for different arches
for lib in "${build_library[@]}"
do
    library_name=$lib
    archive_name=$lib

    # parser_lib_archive_alias=${lib}_archive_alias
    # archive_name=${!parser_lib_archive_alias}

    if [ $lib = "zlib" ]; then
        archive_name=z
    fi

    if [ $lib = "openssl" ];then
        archive_name=ssl
    fi

    mkdir -p $cfg_platform_name/$archive_name/include/

    for arch in "${build_arches[@]}"
    do
        #skip certain arch libraries
        #because luajit doesn't support arm64!
        if [ $lib = "luajit" ] && [ $arch = "arm64" ]; then
            continue
        fi

        #set build mode flags -- debug or release
        set_build_mode_cflags
        

        install_library_path=$cfg_library_install_prefix
        build_library_path=$cfg_library_build_folder

        echo "build $arch for $lib in $cfg_platform_name"

        MY_TARGET_ARCH=$arch
        export MY_TARGET_ARCH
        
        build_settings_for_$cfg_platform_name $arch $lib
        
        echo "MY_TARGET_ARCH := ${MY_TARGET_ARCH}" >> config.mak
        echo "OPTIM := ${OPTIM}" >> config.mak

        cd -    
  
        local_library_install_path=$cfg_platform_name/$archive_name/prebuilt/$arch
        if [ ! -d $local_library_install_path ]; then
            echo "create folder for library with specify arch. $local_library_install_path"
            mkdir -p $local_library_install_path
        fi
        
        cp $top_dir/contrib/$install_library_path/$arch/lib/lib$archive_name.a $local_library_install_path/lib$archive_name.a
        cp $top_dir/contrib/$install_library_path/$arch/lib/lib$archive_name*.a $local_library_install_path/lib$archive_name.a


        if [ $lib = "curl" ]; then
            local_library_install_path=$cfg_platform_name/ssl/prebuilt/$arch 
            mkdir -p $local_library_install_path
            cp $top_dir/contrib/$install_library_path/$arch/lib/libssl.a $local_library_install_path/libssl.a

            local_library_install_path=$cfg_platform_name/crypto/prebuilt/$arch
            mkdir -p $local_library_install_path
            cp $top_dir/contrib/$install_library_path/$arch/lib/libcrypto.a $local_library_install_path/libcrypto.a

        fi

        if [ $lib = "png" ] || [ $lib = "freetype2" ] || [ $lib = "websockets" ] || [ $lib = "curl" ];  then
            echo "copying libz..."
            local_install_path=$cfg_platform_name/z/prebuilt/$arch
            mkdir -p $local_install_path
            cp $top_dir/contrib/$install_library_path/$arch/lib/libz.a $local_install_path/libz.a
        fi

        echo "Copying needed heder files"
        copy_include_file_path=${lib}_header_files
        cp  -r $top_dir/contrib/$install_library_path/$arch/include/${!copy_include_file_path} $cfg_platform_name/$archive_name/include


        echo "cleaning up"
        if [ $cfg_is_cleanup_after_build = "yes" ];then
            rm -rf $top_dir/contrib/$install_library_path
            rm -rf $top_dir/contrib/$build_library_path-$arch
        fi
    done

    if [ $cfg_build_fat_library = "yes" ];then
        
        create_fat_library $archive_name

        if [ $lib = "curl" ]; then
            create_fat_library ssl
            create_fat_library crypto
        fi

        if [ $lib = "png" ] || [ $lib = "curl" ] || [ $lib = "freetype2" ] || [ $lib = "websockets" ]; then
            create_fat_library z
        fi
    fi

done
