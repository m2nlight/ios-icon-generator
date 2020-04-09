#!/usr/bin/env bash
#
# Copyright (C) 2018 smallmuou <smallmuou@163.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is furnished
# to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

spushd() {
    pushd "$1" &>/dev/null
}

spopd() {
    popd &>/dev/null
}

info() {
    local green="\033[1;32m"
    local normal="\033[0m"
    echo -e "[${green}INFO${normal}] $1"
}

cmdcheck() {
    command -v $1 >/dev/null 2>&1 || {
        error >&2 "Please install command $1 first."
        exit 1
    }
}

error() {
    local red="\033[1;31m"
    local normal="\033[0m"
    echo -e "[${red}ERROR${normal}] $1"
}

warn() {
    local yellow="\033[1;33m"
    local normal="\033[0m"
    echo -e "[${yellow}WARNING${normal}] $1"
}

yesno() {
    while true; do
        read -p "$1 (y/n)" yn
        case $yn in
        [Yy])
            $2
            break
            ;;
        [Nn]) exit ;;
        *) echo 'please enter y or n.' ;;
        esac
    done
}

curdir() {
    if [ ${0:0:1} = '/' ] || [ ${0:0:1} = '~' ]; then
        echo "$(dirname $0)"
    elif [ -L $0 ]; then
        name=$(readlink $0)
        echo $(dirname $name)
    else
        echo "$(pwd)/$(dirname $0)"
    fi
}

myos() {
    echo $(uname | tr "[:upper:]" "[:lower:]")
}

#########################################
###           GROBLE DEFINE           ###
#########################################

VERSION=2.0.0+mod_by_m2nlight
AUTHOR=smallmuou

#########################################
###             ARG PARSER            ###
#########################################

usage() {
    prog=$(basename $0)
    cat <<EOF
$prog version $VERSION by $AUTHOR

USAGE: $prog [OPTIONS] srcfile dstpath

MODIFIED DESCRIPTION:
    * Generate AppIcon.appiconset directory and Contents.json file
    * Rewrite the sizes_mapper, will generate icons for Xcode 11.3.1 required
    * modified code follow MIT License

DESCRIPTION:
    This script aim to generate iOS/macOS/watchOS APP icons more easier and simply.

    srcfile - The source png image. Preferably above 1024x1024
    dstpath - The destination path where the icons generate to.

OPTIONS:
    -h      Show this help message and exit

EXAMPLES:
    $prog 1024.png ~/123

EOF
    exit 1
}

while getopts 'h' arg; do
    case $arg in
    h)
        usage
        ;;
    ?)
        # OPTARG
        usage
        ;;
    esac
done

shift $(($OPTIND - 1))

[ $# -ne 2 ] && usage

#########################################
###            MAIN ENTRY             ###
#########################################

cmdcheck sips
src_file=$1
dst_path=$2

# check source file
[ ! -f "$src_file" ] && {
    error "The source file $src_file does not exist, please check it."
    exit -1
}

# check width and height
src_width=$(sips -g pixelWidth $src_file 2>/dev/null | awk '/pixelWidth:/{print $NF}')
src_height=$(sips -g pixelHeight $src_file 2>/dev/null | awk '/pixelHeight:/{print $NF}')

[ -z "$src_width" ] && {
    error "The source file $src_file is not a image file, please check it."
    exit -1
}

if [ $src_width -ne $src_height ]; then
    warn "The height and width of the source image are different, will cause image deformation."
fi

# create dst directory
[[ $dst_path == */AppIcon.appiconset ]] || dst_path="$dst_path/AppIcon.appiconset"
[ ! -d "$dst_path" ] && mkdir -p "$dst_path"

# ios sizes refer to https://developer.apple.com/design/human-interface-guidelines/ios/icons-and-images/app-icon/
# macos sizes refer to https://developer.apple.com/design/human-interface-guidelines/macos/icons-and-images/app-icon/
# watchos sizes refer to https://developer.apple.com/design/human-interface-guidelines/watchos/icons-and-images/home-screen-icons/
#
#
# name size
sizes_mapper=$(
    cat <<EOF
# iPhone / Notification iOS 7-13 / 20pt
icon-20@2x      40
icon-20@3x      60
# iPhone / Settings - iOS 7-13 / 29pt
icon-29@2x      58
icon-29@3x      87
# iPhone / Spotlight / iOS 7-13 / 40pt
icon-40@2x      80
icon-40@3x      120
# iPhone App / iOS 7-13 / 60pt
icon-60@2x      120
icon-60@3x      180

# iPad / Notification iOS 7-13 / 20pt
icon-20-ipad        20
icon-20@2x-ipad     40
# iPad / Settings - iOS 7-13 / 29pt
icon-29-ipad        29
icon-29@2x-ipad     58
# iPad / Spotlight / iOS 7-13 / 40pt
icon-40-ipad        40
icon-40@2x-ipad     80
# iPad App / iOS 7-13 / 76pt
icon-76-ipad        76
icon-76@2x-ipad     152
# iPad Pro (12.9-inch) App / iOS 9-13 / 83.5pt
icon-83.5@2x-ipad   167

# App Store / iOS / 1024pt
icon-1024           1024    ios-marketing
EOF
)

OLD_IFS=$IFS
IFS=$'\n'
srgb_profile='/System/Library/ColorSync/Profiles/sRGB Profile.icc'
contents_file="$dst_path/Contents.json"
cat <<EOF >"$contents_file"
{
    "images": [
EOF

for line in $sizes_mapper; do
    name=$(echo $line | awk '{print $1}')
    if [ -z "$name" ] || [ "${name:0:1}" = '#' ]; then
        continue
    fi
    size=$(echo $line | awk '{print $2}')
    idiom=$(echo $line | awk '{print $3}')
    if [ -z "$idiom" ]; then
        if [[ $name == *-ipad ]]; then
            idiom=ipad
        else
            idiom=iphone
        fi
    fi
    scale='1x'
    if [[ $name == *@* ]]; then
        scale="${name#*@}"
        scale="${scale%-ipad}"
    fi
    nSize=$(echo $name | cut -d'-' -f2 | cut -d'@' -f1)

    info "Generate $name.png ..."
    if [ -f $srgb_profile ]; then
        sips --matchTo '/System/Library/ColorSync/Profiles/sRGB Profile.icc' -z $size $size $src_file --out $dst_path/$name.png >/dev/null 2>&1
    else
        sips -z $size $size $src_file --out $dst_path/$name.png >/dev/null
    fi
    if [ "$idiom" = 'ios-marketing' ]; then
        cat <<EOF >>"$contents_file"
        {
            "size": "${nSize}x${nSize}",
            "idiom": "${idiom}",
            "filename": "${name}.png",
            "scale": "${scale}"
        }
EOF
    else
        cat <<EOF >>"$contents_file"
        {
            "size": "${nSize}x${nSize}",
            "idiom": "${idiom}",
            "filename": "${name}.png",
            "scale": "${scale}"
        },
EOF
    fi
done

cat <<EOF >>"$contents_file"
    ],
    "info": {
        "version": 1,
        "author": "$USER"
    }
}
EOF

info "Congratulation. All icons for iOS/macOS/watchOS APP are generate to the directory: $dst_path."

IFS=$OLD_IFS
