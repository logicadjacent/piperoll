# PipeRoll

Install fresh versions of `PipeWire` and `WirePlumber` on a point-release distro, like `Ubuntu` and `Debian`.

## The big question: WHY?

`PipeWire` and (especially) `WirePlumber` are still "young" projects, and while they bring some crucial features to the Linux desktop, they were pushed to be the default way too soon.
Point-release distros like `Ubuntu` are stuck with older versions, and many things have been redesigned in later versions of these components. These redesigns are important if you want to use features beyond basic audio playback.

This script helps to overcome this problem, it's possible to install multiple version-combinations, not just the latest, in case you want a specific set of ~~bugs~~ features for your setup.

&nbsp;<br/>&nbsp;<br/>

## Installation

Clone this repo:

```bash
git clone https://github.com/logicadjacent/piperoll
cd piperoll
```

First step is to install `PipeWire` and `WirePlumber` on the host system, with whatever version the distro is providing. See [Details](#the-boring-details) for why this is required.

```bash
bash ./setup.sh prepare
```

<details>
<summary>Output</summary>

On `Ubuntu 24.04 Noble` it looks something like this:

```
⎔ WARNING: This step can potentionally replace core audio subsystems!
⎔   If you are not using pipewire already, it will replace your existing audio config!

⎔ Installing host packages...

...
Fetched 6,632 kB in 2s (3,156 kB/s)
Reading package lists... Done
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
pipewire is already the newest version (1.0.5-1).
pipewire-pulse is already the newest version (1.0.5-1).
wireplumber is already the newest version (0.4.17-1ubuntu4).
...
The following additional packages will be installed:
  libatopology2t64 libldacbt-abr2
Suggested packages:
  dialog
The following packages will be REMOVED:
  pulseaudio pulseaudio-module-bluetooth
The following NEW packages will be installed:
  alsa-utils libatopology2t64 libldacbt-abr2 libspa-0.2-bluetooth patchelf pipewire-alsa pipewire-audio-client-libraries
0 upgraded, 7 newly installed, 2 to remove and 0 not upgraded.
Need to get 1,733 kB of archives.
After this operation, 445 kB disk space will be freed.
Do you want to continue? [Y/n] 

```

</details>

After you've made sure nothing scary is listed under `REMOVED` (it should only be `pulseaudio` on older systems), confirm with `Y`.

We can run a test, to make sure the system audio still works for basic audio. The following command will list the running pipewire processes, versions, and will run 3 audio playback tests, via different APIs (`PipeWire`, `pulseaudio` and `alsa`). At least `pulseaudio` and `alsa` should work at this stage.

```bash
bash ./setup.sh test
```

<details>
<summary>Output</summary>

```
⎔ Version info:
pipewire
Compiled with libpipewire 1.0.5
Linked with libpipewire 1.0.5
wireplumber
Compiled with libwireplumber 0.4.17
Linked with libwireplumber 0.4.17
⎔ Processes:
    PID %CPU   RSS  NI PRI CMD
    764  0.0  5024 -11  30 /usr/bin/pipewire
    765  0.0  1296   0  19 /usr/bin/pipewire -c filter-chain.conf
    767  0.0 12356 -11  30 /usr/bin/wireplumber
    769  0.0  2684 -11  30 /usr/bin/pipewire-pulse
⎔ Testing audio playback via pipewire...
⎔ Testing audio playback via pulseaudio...
⎔ Testing audio playback via alsa...
```

</details>

Now we can install the latest version:

```bash
bash ./setup.sh install
```

<details>
<summary>Output</summary>

```
⎔ Installing pipewire to /home/logicadjacent/.local/piperoll...
⎔ Creating directories...
⎔ Downloading packages...
⎔ Building rootfs...
⎔ Creating config files and directories...
⎔ Creating wrapper scripts and systemd units...

⎔ Installation complete!
```

</details>

The new version is ready to be used, so let's enable it:

```bash
bash ./setup.sh enable
```

<details>
<summary>Output</summary>

```
⎔ Enabling pipewire override...
```

</details>

And we should be done! Let's run the test again:

```
bash ./setup.sh test
```

```
⎔ Version info:
/home/logicadjacent/.local/piperoll/rootfs//usr/bin/pipewire
Compiled with libpipewire 1.2.7
Linked with libpipewire 1.2.7
/home/logicadjacent/.local/piperoll/rootfs//usr/bin/wireplumber
Compiled with libwireplumber 0.5.8
Linked with libwireplumber 0.5.8
⎔ Processes:
    PID %CPU   RSS  NI PRI CMD
   3418  0.0  5040 -11  30 /home/logicadjacent/.local/piperoll/rootfs/usr/bin/pipewire
   3420  0.0   528   0  19 /home/logicadjacent/.local/piperoll/rootfs/usr/bin/pipewire -c filter-chain.conf
   3421  0.2 22584 -11  30 /home/logicadjacent/.local/piperoll/rootfs/usr/bin/wireplumber
   3422  0.0  2024 -11  30 /home/logicadjacent/.local/piperoll/rootfs/usr/bin/pipewire-pulse
⎔ "/home/logicadjacent/.local/bin" is not in PATH (yet)! Log out and back in to activate it.
⎔ Testing audio playback via pipewire...
⎔ Testing audio playback via pulseaudio...
⎔ Testing audio playback via alsa...
```

Things to note:
- The version numbers should be higher
- The processes should run from a different path, under `$HOME`
- Most importantly: ALL of the playback methods should work

To finish up, `$HOME/.local/bin` should be added to PATH. This folder contains the various utilities from `PipeWire` and `WirePlumber`, like `pw-top`, `pw-dump`, `wpctl`.
On most systems with `bash`, this happens automatically when logging in. If it doesn't, add it manually to your shell profile.

If you want to go back to using `PipeWire` and `WirePlumber` on the host system, use the following:

```bash
bash ./setup.sh disable
```

```
⎔ Disable pipewire override...
```

## Updating

To update to the latest packages, just run:

```bash
bash ./setup.sh install
bash ./setup.sh enable
```

If any of the version numbers changed, this will create the new rootfs and activate it.

&nbsp;<br/>&nbsp;<br/>

## Configuration file locations
`$HOME/.local/piperoll/etc` is used for the configuration files.

<details>
<summary>Why?</summary>

To avoid conflicts with the host system, we don't use any of the usual config locations (`/usr/share`, `/etc`, `$HOME/.config/`).
This makes it possible to enable/disable this setup, and having a basic setup on the host that still works, even if your custom `PipeWire` config is broken for example.

</details>

#### For extra `PipeWire` configuration snippets, like filter plugins or loopbacks:

`$HOME/.local/piperoll/etc/pipewire/pipewire.conf.d/`

#### `WirePlumber` configuration snippets:

`$HOME/.local/piperoll/etc/wireplumber.conf.d`
### Locking package versions
There is a small configuration file used by `PipeRoll`, creatively named: `config`.

There is an example file:

```
#!/bin/bash

# ⎔ LogicAdjacent 2025 ⎔

# Use this to make the version of a package permanent.
# Useful if you need a specific set of features (and bugs...).
#PACKAGES[pipewire]="1:1.2.7-1"
#PACKAGES[wireplumber]="0.5.8-1"

# Used in the "prepare" stage, to install the main bluetooth packages.
# Normally not needed, the normal ubuntu installation should contain everything already.
#INSTALL_BLUETOOTH="yes"

# Indicates a somewhat older system
# On ubuntu-based systems it should be turned on if it's based on jammy (22.04)
# noble (24.04) is already considered new in this context
# Currently it controls what packages are installed on the host system.
#LEGACY="yes"
```

Uncomment the `PACKAGES[pipewire]` and `PACKAGES[wireplumber]` as needed, and set the version you need; the packages with the specific version must be present in the Arch Linux Archive.


&nbsp;<br/>&nbsp;<br/>


## Tested distros

- Ubuntu 24.04 Noble
- Ubuntu 22.04 Jammy
- Linux Mint 22.01 Xia
- Pop! OS 22.04 (both Xorg and Wayland)
- Zorin OS Core 17.2
- Debian 12 Bookworm
- Arch Linux (Feb 2025)


&nbsp;<br/>&nbsp;<br/>

## The (boring) Details

<details>
As shown during the installation, there are two phases of the procedure:

### Host packages

The first is to make sure that `PipeWire` and `WirePlumber` are installed on the host system.

The purpose of this is to have the package dependencies and client libraries set up correctly, as far as the rest of the system is concerned. It's also nice to have something to fall back to if things don't work out.

Depending on your distro, the default audio system can be `PipeWire` or `Pulseaudio`. If you're still using `Pulseaudio`, this step will replace it.

It will also install a few utilities needed for the next phase.

This is the only part of the procedure that will require root access, the package install step will use sudo for this. Everything else is done as a normal user.

### Pipewire "Container"

This second phase will download the latest/specified versions of `PipeWire`, `WirePlumber` and the bare minimum dependent packages, and unpack them in a *rootfs* directory ($HOME/.local/piperoll/rootfs). Kinda like a container, but not really.

It uses `Arch Linux` binary packages from the `Arch Linux Archive`. This allows us to pick different versions, without having to resort to compiling from source code. `Arch Linux` is one of the best places to find the latest versions of packages, that also go through some testing, before being released publicly.

You can check which version of the packages are available here:

[https://archive.archlinux.org/packages/p/pipewire/](https://archive.archlinux.org/packages/p/pipewire/)

[https://archive.archlinux.org/packages/w/wireplumber/](https://archive.archlinux.org/packages/w/wireplumber/)

Since we're not gonna run this in an actual container, we have to deal with a few things:

#### Library paths

The executables in the binary package expect to be run from /usr/bin, and find their dependent libraries in the usual system folders (/usr/lib and similar). This can be normally be solved using only the environment variable `LD_LIBRARY_PATH`, but in this case it's not enough. The Arch packages depend on a newer `glibc` library than what is on the host system, to fix this, we need to also download `glibc` from Arch, and to patch the executables in the rootfs, to add `RPATH` entries and to set the `Interpreter` (the location of ld-linux.so).

#### Configuration and plugin paths

Most linux programs are compiled with a few hardcoded paths to configuration files, data and plugin directories. Fortunately `PipeWire` and `WirePlumber` provide environment variables that can be used to override these hardcoded paths (eg. PIPEWIRE_CONFIG_DIR , PIPEWIRE_MODULE_DIR , etc...). For this reason, we create wrapper scripts that set up these variables and call the actual executable.

#### Systemd unit overrides

`Systemd` service units are used to launch `PipeWire` and `WirePlumber` on a normal system, located in `/usr/lib/systemd/user/`. To make sure `systemd` launches the executables we just prepared and use the necessary environment variables, we're gonna use an override unit.
This way we don't have to alter the configuration files on the host system. Systemd allows override unit files to be present in a few locations (see `man systemd.unit`), we're using `$HOME/.config/systemd/user`, since that can be installed without root privileges. 
Using an override file also allows us to keep every security feature that systemd provides, just like when we run the host package.

With these three solutions in place, we can now use `PipeWire` and `WirePlumber` to their full potential and actually have some fun with them.
</details>

&nbsp;<br/>&nbsp;<br/>

# FAQ

#### Any problems on Wayland?

Tested on Pop! OS with Gnome, didn't break anything, all of these worked before and after installing `Piperoll`:
- `gstreamer` pipeline that uses `pipewiresrc` (which connects directly to `pipewire`)
- OBS: Screen Capture (both full screen and application window) and `Video Capture Device (Pipewire) BETA`.

#### Why is Arch Linux on the supported distro list?

Running it on Arch-based systems admittedly isn't that useful, but could be used to preserve older versions and switch between them easily.

#### Why are Manjaro and other Arch-based distros NOT on the list?

Although I tried it with Manjaro live usb, didn't really work, the original `jackd` library is involved for some reason on the host system, and I didn't pursue checking that part out, so for now all Arch-based systems other than Arch itself, is considered unfriendly and the install script won't run.

#### I want to use this on a Raspberry PI!

Currently only `x86_64` is supported, since there is no Arch Packages Archive for `aarch64` packages, if that changes some day, I can add support for it. Although the `ArchLinuxARM` project exists, it has no archive repo and AFAIK there's also no API to query the latest version for a package.
And yes, I want to use it on a Raspberry PI as well, so I may just figure something else out for that, soon(ish).

#### No love for MyFavoriteDistroOfTheDay?

I might look into Fedora/Redhat based stuff if there is significant interest for it.
