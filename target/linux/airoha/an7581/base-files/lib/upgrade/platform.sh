RAMFS_COPY_BIN='fitblk fit_check_sign mktemp'

REQUIRE_IMAGE_METADATA=1

airoha_require_ubi_volumes()
{
	local ubidev volume

	ubidev="$(nand_find_ubi ubi)"
	[ -n "$ubidev" ] || {
		echo "UBI is not initialized; create the base volumes from U-Boot recovery."
		return 1
	}

	for volume in "$@"; do
		if ! nand_find_volume "$ubidev" "$volume" >/dev/null; then
			echo "UBI base volume $volume is missing; repair the layout from U-Boot recovery."
			return 1
		fi
	done
}

airoha_require_ubi_layout()
{
	local ubidev fip_volume

	airoha_require_ubi_volumes fip ubootenv ubootenv2 "$@" || return 1
	ubidev="$(nand_find_ubi ubi)"

	fip_volume="$(nand_find_volume "$ubidev" fip)"
	[ "$(cat "/sys/class/ubi/$fip_volume/data_bytes")" -gt 0 ] || {
		echo "The fip volume does not contain BL31/U-Boot; install the boot chain first."
		return 1
	}
}

platform_check_image() {
	local board=$(board_name)

	[ "$#" -gt 1 ] && return 1

	case "$board" in
	nokia,valyrian)
		case "$(uname -r)" in
		5.4.*|6.18.*|7.3|7.3.*) valyrian_upgrade "$1" check; return $? ;;
		esac
		;;
	airoha,an7581-evb-emmc-eagle|\
	airoha,an7581-evb-emmc-kite)
		fit_check_image "$1"; return $?
		;;
	airoha,an7581-evb)
		case "$(uname -r)" in
		5.4.*|6.18.*|7.3|7.3.*) airoha_require_ubi_layout fit && fit_check_image "$1"; return $? ;;
		esac
		;;
	nokia,xg-040g-md)
		nand_do_platform_check "$board" "$1"
		return $?
		;;
	nokia,xg-040g-md-ubi|\
	nokia,xg-040g-md-ubi-usb-sfp)
		# BL2 loads FIP from UBI; U-Boot boots the FIT from the fit volume.
		airoha_require_ubi_layout fit bosa ri || return 1
		fit_check_image "$1"
		return $?
		;;
	gemtek,xr1710g-ubi)
		airoha_require_ubi_volumes fit factory ubootenv ubootenv2 || return 1
		fit_check_image "$1"
		return $?
		;;
	gemtek,xg2010g|\
	fiberhome,hg5382a|\
	fiberhome,hg5585f-ct|\
	fiberhome,hg5585f-cu|\
	unionman,ung00a|\
	znxt,zn504xg-d|\
	znxt,zn515xg-d|\
	h3c,hm2004-du|\
	nokia,xg-040g-tf-ubi|\
	quantum,q1000k-ubi)
		fit_check_image "$1"
		return $?
		;;
	esac

	return 0
}

platform_do_upgrade() {
	local board=$(board_name)

	case "$board" in
		nokia,valyrian)
			case "$(uname -r)" in
			5.4.*|6.18.*|7.3|7.3.*)
				valyrian_upgrade "$1" write || {
					echo "Valyrian upgrade failed; not rebooting automatically." >&2
					exit 1
				}
				;;
			*) nand_do_upgrade "$1" ;;
			esac
			;;
		airoha,an7581-evb-emmc-eagle|\
		airoha,an7581-evb-emmc-kite)
			fit_do_upgrade "$1"
			;;
		airoha,an7581-evb)
			case "$(uname -r)" in
			5.4.*|6.18.*|7.3|7.3.*) airoha_require_ubi_layout fit && fit_do_upgrade "$1" ;;
			*) nand_do_upgrade "$1" ;;
			esac
			;;
		gemtek,xr1710g-ubi|\
		gemtek,w1700k-ubi|\
		quantum,q1000k-ubi)
			fit_do_upgrade "$1"
			;;
		gemtek,xg2010g|\
		fiberhome,hg5382a|\
		fiberhome,hg5585f-ct|\
		fiberhome,hg5585f-cu|\
		unionman,ung00a|\
		znxt,zn504xg-d|\
		znxt,zn515xg-d|\
		h3c,hm2004-du)
			airoha_require_ubi_layout factory && fit_do_upgrade "$1"
			;;
		nokia,xg-040g-md-ubi|\
		nokia,xg-040g-md-ubi-usb-sfp)
			airoha_require_ubi_layout fit bosa ri && fit_do_upgrade "$1"
			;;
		nokia,xg-040g-tf-ubi)
			airoha_require_ubi_layout bosa ri && fit_do_upgrade "$1"
			;;
		*)
			nand_do_upgrade "$1"
			;;
	esac
}
