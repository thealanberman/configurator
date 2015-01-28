#!/bin/bash

# This script makes heavy use of the bash "IF" shorthand.
# IF shorthand is in the format: [TEST/COMMAND] && { IF TRUE, DO THIS} || { IF FALSE, DO THIS }

check_for_admin ()
{
	# clear
	echo "This script must be run with an administrator account."
	echo -n "Please enter your password: "
	unset password
	sudo -k
	while IFS= read -r -n1 -s char; do
		[[ -z $char ]] && { printf '\n'; break; } # ENTER pressed; output \n and break.
		if [[ $char == $'\x7f' ]]; then # backspace was pressed
			# erase '*' to the left.
			[[ -n $password ]] && password=${password:0:${#password}-1}
			printf '\b \b'
	else
		# add typed char to output variable.
		password+=$char
		# print '*' in its stead.
		printf '*'
	  fi
	done
	# hand off password to sudo for verification
	echo $password | sudo -v -S 2>/dev/null || { echo 'Wrong password or this is not an administrator account.' ; check_for_admin; }
}


press_enter ()
{
    echo
    read -p "Press Enter to continue"
    clear
}


main_menu ()
{
	selection=
	until [ "$selection" = "0" ]; do
		get_settings;
		echo "************************"
		echo "CONFIGURATION UTILITY"
		echo "************************"
		echo "1) Create Hidden Admin Account"
		echo "2) Create Non-Hidden User Account"
		echo "3) Set Computer Name"
		echo "4) Install Homebrew and Caskroom"
		echo "5) Delete .AppleSetupDone"
		echo "0) Exit"
		read -e -s -p "Enter selection: " -n 1
		echo
		case $REPLY in
			1 ) create_hidden_admin; press_enter;;
			2 ) create_standard_account; press_enter;;
			3 ) set_computer_name; press_enter;;
			4 ) install_homebrew; press_enter;;
			5 ) delete_applesetupdone; press_enter;;
			0 ) exit 0;;
			* ) echo "Please enter a valid number."; press_enter;;
		esac
	done
}


delete_applesetupdone ()
{
	sudo rm -rf /var/db/.AppleSetupDone
	echo "/var/db/.AppleSetupDone deleted."
}

set_computer_name ()
{
	clear
	echo -n "Current "
	sudo systemsetup -getcomputername
	echo
	echo "Press Enter to keep current name."
	echo
	read -p "Enter new computer name: " NEWNAME
	echo
	[[ "$NEWNAME" = "" ]] && { echo "Nevermind then."; } || { sudo systemsetup -setcomputername "$NEWNAME"; sudo scutil --set ComputerName "$NEWNAME"; sudo scutil --set LocalHostName "$NEWNAME"; sudo scutil --set HostName "$NEWNAME"; }
}

install_homebrew ()
{
	# check if brew is installed
	echo "Checking for Homebrew..."
	if [[ ! -e /usr/local/bin/brew ]]; then
		echo "No Homebrew found. Installing...."
		ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
	else
		echo "Homebrew is already installed!"
	fi

	echo

	# check if Caskroom is installed
	echo "Checking for Caskroom..."
	if [[ ! -e /usr/local/bin/brew-cask ]]; then
		echo "No Caskroom found. Installing..."
		brew install caskroom/cask/brew-cask
	else
		echo "Caskroom is already installed!"
	fi
}

get_settings ()
{
	echo "***********************"
	echo "CURRENT SYSTEM SETTINGS"
	echo "***********************"
	echo `sudo systemsetup -getcomputername`

	# check if Homebrew is installed
	[[ -e /usr/local/bin/brew ]] && { echo "Homebrew is installed."; } || { echo "Homebrew is not installed."; }

	# check if Caskroom is installed
	[[ -e /usr/local/bin/brew-cask ]] && { echo "Caskroom is installed."; } || { echo "Caskroom is not installed."; }

	# get hidden admin status
	ALREADYTHERE=`dscl . -search /Users UniqueID 499 | grep UniqueID | cut -f1`
	[[ -z $ALREADYTHERE ]] && echo "There does not appear to be a hidden admin account." || echo "There is a hidden admin account named '$ALREADYTHERE'."
}


create_hidden_admin ()
{
	# check for hidden account, if yes, ask to overwrite
	ALREADYTHERE=`dscl . -search /Users UniqueID 499 | grep UniqueID | cut -f1`
	if [[ ! -z $ALREADYTHERE ]]; then
		echo
		echo "There is already a hidden account named $ALREADYTHERE."
		read -e -s -p "Overwrite it [y/N]? " -n 1 -r
		[[ $REPLY =~ ^[Yy]$ ]] && { echo "Okay. Overwriting."; } || return 1;
	fi
	echo "Ctrl-C to exit"
	echo
	# prompt for hidden account credentials
	read -p "Hidden admin name [local]: " HIDDENADMIN
	[[ $HIDDENADMIN = "" ]] && HIDDENADMIN="local" || false
	read -s -p "$HIDDENADMIN Password: " PASSWORD
	echo $PASSWORD
	read -s -p "Verify $HIDDENADMIN Password: " VPASSWORD
	echo $VPASSWORD
	while [ "$PASSWORD" != "$VPASSWORD" ]; do
		echo "Passwords don't match. Try again."
		read -s -p "$HIDDENADMIN Password: " PASSWORD
		echo
		read -s -p "Verify $HIDDENADMIN Password: " VPASSWORD
		echo
	done

	# Create user record in directory services
	echo "Creating account $HIDDENADMIN..."
	sudo dscl . -create /Users/$HIDDENADMIN
	sudo dscl . -create /Users/$HIDDENADMIN RealName "$HIDDENADMIN"
	sudo dscl . -create /Users/$HIDDENADMIN UniqueID 499
	sudo dscl . -create /Users/$HIDDENADMIN PrimaryGroupID 20
	sudo dscl . -create /Users/$HIDDENADMIN UserShell /bin/bash
	sudo dscl . -create /Users/$HIDDENADMIN IsHidden 1
	sudo dscl . -passwd /Users/$HIDDENADMIN $PASSWORD

	# Set up a hidden home folder
	sudo dscl . -create /Users/$HIDDENADMIN NFSHomeDirectory /var/.$HIDDENADMIN  # or other hidden location
	sudo cp -R /System/Library/User\ Template/English.lproj /var/.$HIDDENADMIN
	sudo chown -R $HIDDENADMIN:staff /var/.$HIDDENADMIN

	# Grant admin & ARD rights
	sudo dseditgroup -o edit -t user -a $HIDDENADMIN admin
	sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -configure -access -on -users $HIDDENADMIN -privs -all -restart -agent

	# Tell loginwindow not to show the user
	sudo defaults write /Library/Preferences/com.apple.loginwindow Hide500Users -bool TRUE

	# Let 'em know it's done
	echo
	echo "Hidden account $HIDDENADMIN successfully created."
}


create_standard_account ()
{
	NEXTUID=$(dscl . -list /Users UniqueID | awk 'BEGIN{i=0}{if($2>i)i=$2}END{print i+1}')
	echo "Next available UID is $NEXTUID."
	echo

	# prompt for account credentials
	read -p "New user name [ageskiosk]: " NEWUSER
	[[ $NEWUSER = "" ]] && NEWUSER="ageskiosk" || false
	read -s -p "$NEWUSER Password: " PASSWORD
	echo
	read -s -p "Verify $NEWUSER Password: " VPASSWORD
	echo
	while [ "$PASSWORD" != "$VPASSWORD" ]; do
		echo "Passwords don't match. Try again."
		read -s -p "$NEWUSER Password: " PASSWORD
		echo
		read -s -p "Verify $NEWUSER Password: " VPASSWORD
		echo
	done

	echo -n "Creating account $NEWUSER..."
	sudo dscl . -create /Users/$NEWUSER;
	sudo dscl . -create /Users/$NEWUSER RealName "$NEWUSER";
	sudo dscl . -create /Users/$NEWUSER UniqueID $NEXTUID;
	sudo dscl . -create /Users/$NEWUSER PrimaryGroupID 20;
	sudo dscl . -create /Users/$NEWUSER UserShell /bin/bash;
	sudo dscl . -passwd /Users/$NEWUSER $PASSWORD
	sudo dscl . -create /Users/$NEWUSER NFSHomeDirectory /Users/$NEWUSER;
	sudo cp -R /System/Library/User\ Template/English.lproj /Users/$NEWUSER;
	sudo chown -R $NEWUSER:staff /Users/$NEWUSER;
	echo "Done."

	# admin rights?
	read -e -s -p "Administrator rights [y/N]? " -n 1 -r
	[[ $REPLY =~ ^[Yy]$ ]] && { sudo dseditgroup -o edit -t user -a $NEWUSER admin; } || false;

	# ARD access?
	read -e -s -p "Remote Administrator rights [y/N]? " -n 1 -r
	[[ $REPLY =~ ^[Yy]$ ]] && { sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -activate -configure -access -on -users $NEWUSER -privs -all -restart -agent; } || false;

}

clear
check_for_admin
clear
main_menu