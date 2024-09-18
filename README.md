
![0](https://github.com/zTnR/mpv-osc-tog4in1/blob/main/preview/Preview0.jpg)

UI 1 is based on mpv-modern-x-compact.

UI 2 is based on vanilla PotPlayer.

# Concept

Giving access to functionalities and OSC customization directly through the OSC without having to modifiy the script.

- Switch between 2 OSC, and 2 minimal versions of them.
- Change seekbar color / height
- On top : on / off / while playing
- Chapters : on / off
- Thumbfast : on / off
- Tooltips : on / off
- OSC mode : always hide / show on pause / always show
- OSC behaviour : show on cursor move on / off
- Modify subtitles vertical positioning
- Modify hide / fade timeouts

Changes are saved in a **_saveparams.ini_** file in the root directory.

Extra buttons can be hidden by right-clicking on the _show Statistics_ one.

# Installation

In the root ```mpv``` or ```mpvnet``` directory :

[tog4in1.lua](https://github.com/zTnR/mpv-osc-tog4in1/blob/main/tog4in1.lua) in the ```script``` folder.

Copy the ```font``` folder.

In _mpv.conf_ : 
```
#remove borders to have access to the top right icons, switching UI using the maximize window one

border=no
```

Compatible with [thumbfast](https://github.com/po5/thumbfast)

# Tog4in1

![1](https://github.com/zTnR/mpv-osc-tog4in1/blob/main/preview/Preview1.png)

![2](https://github.com/zTnR/mpv-osc-tog4in1/blob/main/preview/Preview2.png)

![2](https://github.com/zTnR/mpv-osc-tog4in1/blob/main/preview/Preview3.png)

![4](https://github.com/zTnR/mpv-osc-tog4in1/blob/main/preview/Preview4.png)

# Buttons / Other

### Top right corner

```
Maximized window button has been replaced and switches between the 2 main UIs instead.
```

### Seekbar

```
- Left timer   > Left click     : Show / hide title in OSC
- Left timer   > Right click    : Show / hide title in top bar

- Right timer  > Right click    : Shitch between default / minimal UI versions

- Seekbar      > Right click    : Chapters on / off
- Seekbar      > Mouse wheel    : Increase / decrease seekbar height
```

### Buttons

```
- Play button       > Right clic      : Cycle seekbar / hover colors

- Toggle on top     > Left click      : On / off
- Toggle on top     > Right click     : While playing

- Toggle osc mode   > Left clic       : switch OSC default / on pause / always
- Toggle osc mode   > Right clic      : show OSC on mouse move on / off
- Toggle osc mode   > Mouse wheel     : increase / decrease hide timeout
- Toggle osc mode   > Shift + wheel   : increase / decrease fade timeout

- Toggle statistics > Left clic       : Show statistics
- Toggle statistics > Right clic      : Show / hide extra buttons

- Toggle tooltips   > Left click      : On / off
- Toggle thumbfast  > Left click      : On / off
- Toggle loop       > Left click      : Loop current file on / off

- Toggle subtitles  > Left clic       : Next subtitle
- Toggle subtitles  > Right clic      : Display subtitle list osd
- Toggle subtitles  > Mouse wheel     : Subtitle position up / down

- Toggle audio      > Left clic       : Next audio track
- Toggle audio      > Right clic      : display audio track list osd
```

# Specifics

New parameters in _user_opts_

```
-- tog4in1

modernTog = true,            -- Default UI (true) or PotPlayer-like UI (false)
minimalUI = false,           -- Minimal UI (chapters disabled)
UIAllWhite = false,          -- UI all white (no grey buttons / text)
saveFile = true,             -- Minimal UI (chapters disabled)
minimalSeekY = 30,           -- Height minimal UI
jumpValue = 5,               -- Default jump value in s (From OSC only)
smallIcon = 20,              -- Dimensions in px of small icons
seekbarColorIndex = 8,       -- Default OSC seekbar color (oscPalette)
seekbarHeight = 0,           -- seekbar height offset
showInfos = false,           -- Toggle Statistics
showThumbfast = true,        -- Toggle Thumbfast
showTooltip = true,          -- Toggle Tooltips 
showChapters = false,        -- Toggle chapters on / off
showTitle = false,           -- show title in OSC
showIcons = true,            -- show 'advanced buttons'
onTopWhilePlaying = true,    -- Toggle On top while playing
oscMode = "default",         -- Toggle OSC Modes default / onpause / always
heightoscShowHidearea = 120, -- Height show / hide osc area
``` 

# Credits

Base : [mpv-modern-x-compact](https://github.com/1-minute-to-midnight/mpv-modern-x-compact)

Lists : [mpv-osc-tethys](https://github.com/Zren/mpv-osc-tethys)

On top while playing : https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/ontop-playback.lua

Saving params in file : https://github.com/mpv-player/mpv/issues/3201#issuecomment-2016505146


