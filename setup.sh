#!/bin/bash

# ⎔ LogicAdjacent 2025 ⎔

set -e

# common variables
ARG0="$( readlink -e "$0" )"
NAME="piperoll"
TARGET="${HOME}/.local/${NAME}"


usage() {
	cat <<EOF
Usage:

# Install host packages
bash ${ARG0} prepare

# Set up the new pipewire enviroment in "$TARGET"
bash ${ARG0} install

# Enable the new pipewire environment (systemd override units, wrapper scripts)
bash ${ARG0} enable

# Disable the new pipewire environment, restore system pipewire
bash ${ARG0} disable
EOF
	exit 1
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
	usage
fi



# more variables
BD="$( dirname "$ARG0" )"
ARCHIVE_DIR="${TARGET}/archive"
ROOTFS="${TARGET}/rootfs"
MIRROR="https://archive.archlinux.org/packages/"
NOW="$( date +%s )"
if [ -z "${ARCH}" ]; then
	ARCH="$( uname -m )"
fi
TMP_DIR="${TARGET}/tmp"
BIN_DIR="${TARGET}/bin"
ETC_DIR="${TARGET}/etc"


INSTALL_BLUETOOTH="no"
INSTALL_GLIBC="yes"


# ANSI color definitions
CLR_RED="\e[31m"
CLR_RED_BOLD="\e[1;31m"
CLR_GREEN="\e[32m"
CLR_GREEN_BOLD="\e[1;32m"
CLR_YELLOW="\e[33m"
CLR_YELLOW_BOLD="\e[1;33m"
CLR_BLUE="\e[34m"
CLR_BLUE_BOLD="\e[1;34m"
CLR_MAGENTA="\e[35m"
CLR_MAGENTA_BOLD="\e[1;35m"
CLR_CYAN="\e[36m"
CLR_CYAN_BOLD="\e[1;36m"
CLR_GRAY="\e[37m"
CLR_GRAY_BOLD="\e[1;37m"
CLR_END="\e[0m"




# load OS info
while IFS='=' read -r key value; do
	key="OS_${key}"
	value="${value//\"/}"
	declare "$key=$value"
done < /etc/os-release
DISTRO="${OS_ID}"
OS_VERSION_MAJOR="${OS_VERSION_ID%%.*}"
OS_VERSION_MINOR="${OS_VERSION_ID#*.}"
# echo "${DISTRO} ${OS_VERSION_MAJOR} ${OS_VERSION_MINOR}"

DISTRO_GROUP=""
case "${DISTRO}" in
	ubuntu|linuxmint|pop|zorin)
		DISTRO_GROUP="ubuntu"
	;;
	debian)
		DISTRO_GROUP="debian"
	;;
	arch)
		DISTRO_GROUP="arch"
	;;
	*)
		echo "Unknown distro: ${DISTRO}" >&2; exit 1
	;;
esac

if [ "${ARCH}" != "x86_64" ]; then
	echo -e "${CLR_RED_BOLD}⎔ Unsupported architecture!${CLR_END}"; exit 1
fi

# detect older os
LEGACY="no"
case "${DISTRO_GROUP}" in
	ubuntu|debian)

		case "${DISTRO}" in
			ubuntu)
				if [ "${OS_VERSION_MAJOR}" -lt 24 ]; then
					LEGACY="yes"
				fi
			;;
			debian)
				if [ "${OS_VERSION_MAJOR}" -lt 12 ]; then
					LEGACY="yes"
				fi
			;;
			zorin)
				if [ "${OS_VERSION_MAJOR}" -lt 18 ]; then
					LEGACY="yes"
				fi
			;;
		esac
	;;
	arch)
	;;
	*)
		echo -e "${CLR_RED_BOLD}⎔ Untested/unsupported OS!${CLR_END}"; exit 1
	;;
esac

# Arch package list, grouped by version number.
declare -A PACKAGES
PACKAGES[pipewire]="latest"
PACKAGES_pipewire=(
	a/alsa-card-profiles/alsa-card-profiles-%%VERSION%%-%%ARCH%%.pkg.tar.zst
	l/libpipewire/libpipewire-%%VERSION%%-%%ARCH%%.pkg.tar.zst
	p/pipewire/pipewire-%%VERSION%%-%%ARCH%%.pkg.tar.zst
	p/pipewire-audio/pipewire-audio-%%VERSION%%-%%ARCH%%.pkg.tar.zst
	p/pipewire-jack/pipewire-jack-%%VERSION%%-%%ARCH%%.pkg.tar.zst
	p/pipewire-libcamera/pipewire-libcamera-%%VERSION%%-%%ARCH%%.pkg.tar.zst
	p/pipewire-pulse/pipewire-pulse-%%VERSION%%-%%ARCH%%.pkg.tar.zst
	p/pipewire-roc/pipewire-roc-%%VERSION%%-%%ARCH%%.pkg.tar.zst
	p/pipewire-zeroconf/pipewire-zeroconf-%%VERSION%%-%%ARCH%%.pkg.tar.zst
	p/pipewire-v4l2/pipewire-v4l2-%%VERSION%%-%%ARCH%%.pkg.tar.zst
)
PACKAGES[wireplumber]="latest"
PACKAGES_wireplumber=(
	l/libwireplumber/libwireplumber-%%VERSION%%-%%ARCH%%.pkg.tar.zst
	w/wireplumber/wireplumber-%%VERSION%%-%%ARCH%%.pkg.tar.zst
)
PACKAGES[lua]="latest"
PACKAGES_lua=(
	l/lua/lua-%%VERSION%%-%%ARCH%%.pkg.tar.zst
)

# Binaries that will have a wrapper script, and will be added to the users' PATH.
APPS=(
	pipewire
	pipewire-pulse
	pw-cli
	pw-config
	pw-dump
	pw-link
	pw-loopback
	pw-metadata
	pw-top
	wireplumber
	wpexec
	wpctl
)


# This can be overridden in the config, if extra steps are needed.
post_install() {
	true
}

# Load a config file; can be used to lock package versions
. "${BD}/config"
# Load an optional override config. Useful for temporary overrides that can be excluded from git.
if [ -e "${BD}/config.override" ]; then
	. "${BD}/config.override"
fi


if [ "${INSTALL_GLIBC}" = "yes" ]; then
	PACKAGES[glibc]="latest"
	PACKAGES_glibc=(
		g/glibc/glibc-%%VERSION%%-%%ARCH%%.pkg.tar.zst
	)

	PACKAGES[gcc-libs]="latest"
	PACKAGES_gcc_libs=(
		g/gcc-libs/gcc-libs-%%VERSION%%-%%ARCH%%.pkg.tar.zst
	)
fi


# The only step that requires root privilege is installing ubuntu packages on the host system, the rest is user-mode only.
check_user() {
	if [ "${USER}" = "root" ]; then
		echo "Don't run with sudo..." >&2; exit 1
	fi
}

trap_install() {
	if [ "$?" = "0" ]; then
		echo -e "${CLR_GREEN_BOLD}\n⎔ Installation complete!\n${CLR_END}" >&2
	else
		echo -e "${CLR_RED_BOLD}\n⎔ Installation failed!\n${CLR_END}" >&2
	fi
}


install_host_utils() {
	# Install the required host packages.
	# Pipewire/wireplumber must exist on the host, so the package dependencies are not broken and
	# the pipewire/pulseaudio client libraries on the host will still be used to connect to the pipewire service.

	echo -e "${CLR_YELLOW_BOLD}⎔ WARNING: This step can potentionally replace core audio subsystems!${CLR_END}" >&2
	echo -e "${CLR_YELLOW_BOLD}⎔   If you are not using pipewire already, it will replace your existing audio config!${CLR_END}\n" >&2

	echo -e "${CLR_GREEN_BOLD}⎔ Installing host packages...${CLR_END}" >&2
	case "${DISTRO_GROUP}" in
		ubuntu|debian)
			HOST_PACKAGES=(
				patchelf
				pipewire
				pipewire-pulse
				wireplumber
				pipewire-audio-client-libraries
				rtkit
				alsa-utils
				wget
				jq
				zstd
				pulseaudio-utils
				pavucontrol
			)
			if [ "${LEGACY}" = "yes" ]; then
				HOST_PACKAGES+=(
				)
			else
				HOST_PACKAGES+=(
					pipewire-alsa
					pipewire-jack
				)
			fi

			if [ "${INSTALL_BLUETOOTH}" = "yes" ]; then
				HOST_PACKAGES+=(
					bluez
					blueman
					bluez-obexd
					libspa-0.2-bluetooth
				)
			fi

			sudo apt-get update || true
			sudo apt-get install "${HOST_PACKAGES[@]}"

			# This step also fixes the jack integration, Ubuntu deemed this optional...
			if [ ! -e "/etc/ld.so.conf.d/pipewire-jack-${ARCH}-linux-gnu.conf" ]; then
				cat <<EOF | sudo tee "/etc/ld.so.conf.d/pipewire-jack-${ARCH}-linux-gnu.conf" >/dev/null
$( find "/usr/lib/" -path '*/pipewire-*/jack' )
EOF
				sudo ldconfig
			fi
		;;
		arch)
			if [ "${DISTRO}" != "arch" ]; then
				echo -e "${CLR_RED_BOLD}Your distro is too opinionated, preventing disaster!${CLR_END}" >&2; exit 1
			fi
			HOST_PACKAGES=(
				patchelf
				pipewire
				pipewire-pulse
				pipewire-alsa
				pipewire-jack
				wireplumber
				rtkit
				alsa-utils
				wget
				jq
				zstd
				libpulse
				pavucontrol
			)

			if [ "${INSTALL_BLUETOOTH}" = "yes" ]; then
				HOST_PACKAGES+=(
					bluez
					blueman
					bluez-obex
				)
			fi

			sudo pacman -Syu --needed "${HOST_PACKAGES[@]}"
		;;
	esac
}



# Check the latest version for a package, and cache the info for a day.
get_package_latest_version() {
	local PKG="${1}"
	local PKG_JSON="${TMP_DIR}/pkg-info--${PKG}.json"
	local PKG_JSON_TS
	PKG_JSON_TS="$( stat --format="%Y" "${PKG_JSON}" 2>/dev/null || echo "0" )"
	if [ "$(( NOW - PKG_JSON_TS ))" -gt 86400 ]; then
		wget -q -O "${PKG_JSON}" "https://archlinux.org/packages/search/json/?name=${PKG}"
	fi
	jq -r '.results[0] | .pkgver as $pkgver | .pkgrel as $pkgrel | .epoch as $epoch | if $epoch != null and $epoch != 0 then ($epoch|tostring) + ":" + $pkgver + "-" + $pkgrel else $pkgver + "-" + $pkgrel end' "${PKG_JSON}"
}


gather_service_list() {
	SERVICES=( pipewire pipewire-pulse wireplumber )
	SYSTEMD_SERVICES=( pipewire.service pipewire-pulse.service wireplumber.service )
	if [ -e "/usr/lib/systemd/user/filter-chain.service" ]; then
		SERVICES+=( filter-chain )
		SYSTEMD_SERVICES+=( filter-chain.service )
	fi
}



setup_dirs() {
	echo -e "${CLR_GREEN_BOLD}⎔ Creating directories...${CLR_END}" >&2
	mkdir -p \
		"${TARGET}" \
		"${ARCHIVE_DIR}" \
		"${ETC_DIR}" \
		"${TMP_DIR}" \
		"${BIN_DIR}"
}

setup_config_dirs() {
	echo -e "${CLR_GREEN_BOLD}⎔ Creating config files and directories...${CLR_END}" >&2
	mkdir -p \
		"${ETC_DIR}/pipewire/pipewire.conf.d" \
		"${ETC_DIR}/pipewire/pipewire-pulse.conf.d" \
		"${ETC_DIR}/pipewire/client.conf.d" \
		"${ETC_DIR}/pipewire/jack.conf.d" \
		"${ETC_DIR}/pipewire/filter-chain.conf.d" \
		"${ETC_DIR}/wireplumber/wireplumber.conf.d" \
		"${ETC_DIR}/wireplumber/scripts"

	# We need to create symlinks to the target/etc directory for the config files.
	# Normally pipewire will check /usr/share/pipewire, /etc/pipewire and ~/.config/pipewire,
	# but we want to avoid all of those folders, and just use the target/etc.
	# Unfortunately when an override directory is given, only that folder is scanned, target/usr/share/pipewire isn't,
	# hence the need for the links from target/usr/share/pipewire to target/etc.
	local CONF
	for CONF in "pipewire/pipewire.conf" "pipewire/pipewire-pulse.conf" "pipewire/client.conf" "pipewire/jack.conf" "pipewire/filter-chain.conf" "wireplumber/wireplumber.conf"; do
		if [ ! -e "${ETC_DIR}/${CONF}" ]; then
			ln -s "${ROOTFS}/usr/share/${CONF}" "${ETC_DIR}/${CONF}"
		fi
		if [ -e "${ROOTFS}/usr/share/${CONF}.d" ]; then
			local FN
			while read -r FN; do
				local BN="${FN##*/}"
				if [ ! -e "${ETC_DIR}/${CONF}.d/${BN}" ]; then
					ln -sf "${FN}" "${ETC_DIR}/${CONF}.d/${BN}"
				fi
			done < <(find "${ROOTFS}/usr/share/${CONF}.d" -mindepth 1 -maxdepth 1 -name '*.conf')
		fi
	done
}

setup_rootfs() {
	local VERSIONS=()
	local PACKAGES_=()
	local PKG_GROUP

	echo -e "${CLR_GREEN_BOLD}⎔ Downloading packages...${CLR_END}" >&2

	# For each package group, check the latest version,
	# and download the package archives if missing.
	for PKG_GROUP in "${!PACKAGES[@]}"; do
		local PKG_VERSION="${PACKAGES[$PKG_GROUP]}"
		if [ "${PKG_VERSION}" = "latest" ]; then
			PKG_VERSION="$( get_package_latest_version "${PKG_GROUP}" )"
		fi
		# echo "${PKG_GROUP}: ${PKG_VERSION}"

		VERSIONS+=("${PKG_VERSION}")
		declare -n PKG_LIST="PACKAGES_${PKG_GROUP/-/_}"
		local PKG
		for PKG in "${PKG_LIST[@]}"; do
			local PKG_URL="${MIRROR}/${PKG}"
			PKG_URL="${PKG_URL//%%VERSION%%/${PKG_VERSION}}"
			PKG_URL="${PKG_URL//%%ARCH%%/${ARCH}}"
			local PKG_NAME="${PKG_URL##*/}"
			PACKAGES_+=("${PKG_NAME}")
			# echo "${PKG}   ${PKG_NAME}   ${PKG_URL}"
			if [ ! -e "${ARCHIVE_DIR}/${PKG_NAME}" ]; then
				wget -q --timestamping -P "${ARCHIVE_DIR}" "${PKG_URL}"
			fi
		done
	done

	local ROOTFS_VERSIONED
	# Merge the package group version, use it in the rootfs name, so we can have multiple versions,
	# and switch between them if needed.
	ROOTFS_VERSIONED="$( IFS='_'; echo "${TARGET}/rootfs--${VERSIONS[*]}" )"

	rm -f "${TARGET}/rootfs"
	ln -sf "${ROOTFS_VERSIONED##*/}" "${TARGET}/rootfs"

	if [ ! -e "${ROOTFS_VERSIONED}" ]; then
		# Unpack the packages in the rootfs
		echo -e "${CLR_GREEN_BOLD}⎔ Building rootfs...${CLR_END}" >&2
		mkdir -p "${ROOTFS_VERSIONED}"

		local PKG_NAME
		for PKG_NAME in "${PACKAGES_[@]}"; do
			tar -C "${ROOTFS}" --zstd -xf "${ARCHIVE_DIR}/${PKG_NAME}"
		done

		# newer systems have merged usr
		if [ ! -e "${ROOTFS}/lib" ]; then ln -s "usr/lib" "${ROOTFS}/lib"; fi
		if [ ! -e "${ROOTFS}/lib64" ]; then ln -s "lib" "${ROOTFS}/lib"; fi
		if [ ! -e "${ROOTFS}/bin" ]; then ln -s "usr/bin" "${ROOTFS}/bin"; fi
		if [ ! -e "${ROOTFS}/sbin" ]; then ln -s "bin" "${ROOTFS}/sbin"; fi

		if [ "${INSTALL_GLIBC}" = "yes" ]; then
			# LD_LIBRARY_PATH is not enough to make two glibc's coexist, need a bit of ELF magic inside the rootfs.
			find "${ROOTFS}/usr/lib" \
				-name '*.so*' -a \
				-type f -a \
				! -name 'ld-linux-*' \
				-exec patchelf --add-rpath "${ROOTFS}/usr/lib" {} \; 2>/dev/null

			find "${ROOTFS}/usr/bin" \
				-type f \
				-exec patchelf --add-rpath "${ROOTFS}/usr/lib" {} \; 2>/dev/null

			local INTERP
			INTERP="$( find "${ROOTFS}/usr/lib/" -name "ld-linux-*.so*" | head -n 1 )"

			if [ -z "${INTERP}" ]; then
				echo "Can't find ld-linux-*.so*..." >&2; exit 1
			fi
			find "${ROOTFS}/usr/lib" \
				-name '*.so*' -a \
				-type f -a \
				! -name 'ld-linux-*' \
				-exec patchelf --set-interpreter "${INTERP}" {} \; 2>/dev/null

			find "${ROOTFS}/usr/bin" \
				-type f \
				-exec patchelf --set-interpreter "${INTERP}" {} \; 2>/dev/null
		fi
	fi
}

create_wrappers() {
	echo -e "${CLR_GREEN_BOLD}⎔ Creating wrapper scripts and systemd units...${CLR_END}" >&2

	gather_service_list

	local PIPEWIRE_MODULE_DIR
	PIPEWIRE_MODULE_DIR="$( basename "$( find "${ROOTFS}/usr/lib" -maxdepth 1 -name 'pipewire-*' | head -n1 )" )"
	local SPA_PLUGIN_DIR
	SPA_PLUGIN_DIR="$( basename "$( find "${ROOTFS}/usr/lib" -maxdepth 1 -name 'spa-*' | head -n1 )" )"
	local WIREPLUMBER_MODULE_DIR
	WIREPLUMBER_MODULE_DIR="$( basename "$( find "${ROOTFS}/usr/lib" -maxdepth 1 -name 'wireplumber-*' | head -n1 )" )"

	local SCRIPT_TEMPLATE
	SCRIPT_TEMPLATE="$( cat <<EOF

export PATH="${BIN_DIR}:${ROOTFS}/usr/bin:\${PATH}"
export LD_LIBRARY_PATH="${ROOTFS}/usr/lib:\${LD_LIBRARY_PATH}"

export PIPEWIRE_CONFIG_DIR="${TARGET}/etc/pipewire"
export PIPEWIRE_MODULE_DIR="${ROOTFS}/usr/lib/${PIPEWIRE_MODULE_DIR}"

export SPA_PLUGIN_DIR="${ROOTFS}/usr/lib/${SPA_PLUGIN_DIR}"
export SPA_DATA_DIR="${ROOTFS}/usr/share/${SPA_PLUGIN_DIR}"

export WIREPLUMBER_CONFIG_DIR="${TARGET}/etc/wireplumber"
export WIREPLUMBER_MODULE_DIR="${ROOTFS}/usr/lib/${WIREPLUMBER_MODULE_DIR}"
export WIREPLUMBER_DATA_DIR="${ROOTFS}/usr/share/wireplumber"

${SCRIPT_TEMPLATE_ADDONS}

EOF
)"

	# This can be included in any bash script to have the necessary environment variables.
	cat <<EOF >"${BIN_DIR}/pw-env"
#!/bin/bash
# use it as an include:
# source "${BIN_DIR}/pw-env"
${SCRIPT_TEMPLATE}
EOF

	# For debugging. Provides a shell with the environment variables set up.
	cat <<EOF >"${BIN_DIR}/pw-bash"
#!/bin/bash
set -e
${SCRIPT_TEMPLATE}
/bin/bash "\$@"
EOF
	chmod a+x "${BIN_DIR}/pw-bash"

	# Helper utility for quickly restarting things correctly
	cat <<EOF >"${BIN_DIR}/pw-restart"
#!/bin/bash
systemctl restart --user pipewire.socket pipewire-pulse.socket ${SYSTEMD_SERVICES[@]}
EOF
	chmod a+x "${BIN_DIR}/pw-restart"

	# Wrappers for all the defined applications
	local APP
	for APP in "${APPS[@]}"; do
		local BIN="/usr/bin/${APP}"
		local FN="${BIN_DIR}/${APP}"
		cat <<EOF >"${FN}"
#!/bin/bash
set -e
${SCRIPT_TEMPLATE}
"${ROOTFS}/${BIN}" "\$@"
EOF
		chmod a+x "${FN}"
	done

	# Prepare the systemd unit overrides to set up the environment variables and the executable path.
	for SRV in "${SERVICES[@]}"; do
		mkdir -p "${TARGET}/systemd/user/${SRV}.service.d"
		SRV_EXE="${SRV}"
		SRV_ARGS=""
		if [ "${SRV}" = "filter-chain" ]; then
			SRV_EXE="pipewire"
			SRV_ARGS=" -c ${SRV}.conf"
		fi
		cat <<EOF >"${TARGET}/systemd/user/${SRV}.service.d/override.conf"
[Service]
Environment=LD_LIBRARY_PATH="${ROOTFS}/usr/lib"

Environment=PIPEWIRE_CONFIG_DIR="${TARGET}/etc/pipewire"
Environment=PIPEWIRE_MODULE_DIR="${ROOTFS}/usr/lib/${PIPEWIRE_MODULE_DIR}"

Environment=SPA_PLUGIN_DIR="${ROOTFS}/usr/lib/${SPA_PLUGIN_DIR}"
Environment=SPA_DATA_DIR="${ROOTFS}/usr/share/${SPA_PLUGIN_DIR}"

Environment=WIREPLUMBER_CONFIG_DIR="${TARGET}/etc/wireplumber"
Environment=WIREPLUMBER_MODULE_DIR="${ROOTFS}/usr/lib/${WIREPLUMBER_MODULE_DIR}"
Environment=WIREPLUMBER_DATA_DIR="${ROOTFS}/usr/share/wireplumber"

ExecStart=
ExecStart="${ROOTFS}/usr/bin/${SRV_EXE}" ${SRV_ARGS}
EOF
	done
}

restart() {
	gather_service_list
	echo -e "${CLR_YELLOW_BOLD}⎔ Restarting ${NAME}...${CLR_END}"
	systemctl restart --user pipewire.socket pipewire-pulse.socket "${SYSTEMD_SERVICES[@]}"
}

enable() {
	echo -e "${CLR_YELLOW_BOLD}⎔ Enabling ${NAME} override...${CLR_END}"

	local SRV
	gather_service_list
	# Set up the overrides, which allows us to change the pipewire instance, without touching the host system
	for SRV in "${SYSTEMD_SERVICES[@]}"; do
		mkdir -p "${HOME}/.config/systemd/user/${SRV}.d"
		cp "${TARGET}/systemd/user/${SRV}.d/override.conf" "${HOME}/.config/systemd/user/${SRV}.d/override.conf"
	done

	systemctl --user daemon-reload
	if ( systemctl --user is-active pipewire-media-session.service >/dev/null); then
		systemctl --user stop pipewire-media-session.service
		systemctl --user disable pipewire-media-session.service
		systemctl --user enable wireplumber.service
	fi
	systemctl restart --user pipewire.socket pipewire-pulse.socket "${SYSTEMD_SERVICES[@]}"

	mkdir -p "${HOME}/.local/bin"
	local APP
	# Add links to the wrappers. Might need to log out/back in to activate.
	for APP in "${APPS[@]}"; do
		local FN="${BIN_DIR}/${APP}"
		ln -sf "${FN}" "${HOME}/.local/bin/${APP}"
	done
}

disable() {
	echo -e "${CLR_BLUE_BOLD}⎔ Disable ${NAME} override...${CLR_END}"

	local SRV
	gather_service_list
	# Restore things to the host system
	for SRV in "${SYSTEMD_SERVICES[@]}"; do
		rm -f "${HOME}/.config/systemd/user/${SRV}.d/override.conf"
	done

	systemctl --user daemon-reload
	systemctl restart --user pipewire.socket pipewire-pulse.socket "${SYSTEMD_SERVICES[@]}"

	local APP
	for APP in "${APPS[@]}"; do
		rm -f "${HOME}/.local/bin/${APP}"
	done
}

status() {
	echo -e "${CLR_CYAN_BOLD}⎔ Version info:${CLR_END}" >&2
	( bash -l -c "pipewire --version" || true )
	( bash -l -c "wireplumber --version" || true )

	echo -e "${CLR_CYAN_BOLD}⎔ Processes:${CLR_END}" >&2
	ps --format "pid,%cpu,rss,nice,pri,cmd" -C pipewire,pipewire-pulse,pipewire-media-session,wireplumber

	ACTUAL_PW_PATH="$( which pipewire )"
	if [ "${ACTUAL_PW_PATH::4}" = "/usr" ]; then
		echo -e "${CLR_RED_BOLD}⎔ \"${HOME}/.local/bin\" is not in PATH (yet)! Log out and back in to activate it.${CLR_END}" >&2

	fi
}


print_versions() {
	echo -e "${CLR_CYAN_BOLD}⎔ Packages that would be installed:${CLR_END}" >&2
	for PKG_GROUP in "${!PACKAGES[@]}"; do
		local PKG_VERSION="${PACKAGES[$PKG_GROUP]}"
		if [ "${PKG_VERSION}" = "latest" ]; then
			PKG_VERSION="$( get_package_latest_version "${PKG_GROUP}" )"
		fi
		echo "${PKG_GROUP}: ${PKG_VERSION}"
	done
}





ACTION="$1"
shift
case "${ACTION}" in
	prepare)
		install_host_utils
	;;
	install)
		check_user

		echo -e "${CLR_GREEN_BOLD}⎔ Installing ${NAME} to ${TARGET}...${CLR_END}" >&2

		trap trap_install EXIT

		setup_dirs
		setup_rootfs
		setup_config_dirs
		create_wrappers
		post_install
	;;
	enable)
		enable
	;;
	disable)
		disable
	;;
	restart)
		restart
	;;
	status)
		status
	;;
	versions)
		print_versions
	;;
	test)
		status

		echo -e "${CLR_CYAN_BOLD}⎔ Testing audio playback via pipewire...${CLR_END}" >&2
		( bash -l -c "pw-play /usr/share/sounds/alsa/Front_Center.wav" ) || true
		echo -e "${CLR_CYAN_BOLD}⎔ Testing audio playback via pulseaudio...${CLR_END}" >&2
		( bash -l -c "paplay /usr/share/sounds/alsa/Front_Center.wav" ) || true
		echo -e "${CLR_CYAN_BOLD}⎔ Testing audio playback via alsa...${CLR_END}" >&2
		( bash -l -c "aplay -q /usr/share/sounds/alsa/Front_Center.wav" ) || true
	;;
	*)
		usage
	;;
esac

