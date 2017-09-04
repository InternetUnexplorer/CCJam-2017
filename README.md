# WIRES - AsciiDots Editor for CC

Wires is an editor for [AsciiDots](https://github.com/aaronduino/asciidots) programs which runs in ComputerCraft. It has lots of neat features, such as support for multiple tabs, code indexing, custom themes, and more.

> **Note:** This was originally intended to be an AsciiDots interpreter, and my submission for CCJam 2017, however due to poor planning (and getting sick), I was unable to submit the project in time for the competition. I was graciously granted a three-day extension, but after several days with almost no time to work whatsoever, I decided to ditch the interpreter and submit the project as just an editor. I'm very sorry it took this long (the program has been ready to submit for >5 days now, I just haven't had the time to write this README), and I appreciate your patience. Even if you won't count it as a submission, please do download it and give it a try, and tell me how it goes :)

## Features

**Multiple Tabs**

Tabs let you switch between files quickly, which can be useful if you're working with libraries or comparing versions.

**Code Indexing**

Wires keeps track of everything in your file, reparsing lines as you change them. This isn't only for syntax highlighting; it allows you to do things such as jumping to a warp's declaration or opening a library by placing the cursor on its name.

**Themes**

All of the colors used for the tabs, editor, and status bar are user customizable. A detailed guide to creating and using themes will be available "soon".


## Usage


### Getting Started

You can download the latest version of Wires using `wget` (link has been shortened for convenience):

`wget https://goo.gl/4r1kv4 wires`

You can now run the program, optionally passing some files to open as arguments:

`wires [filenames]`

If everything works correctly, you should be greeted with a screen that looks like this:

![The Editor](https://i.imgur.com/uEaNQzd.png)

### Sections

This should be pretty familiar to anyone who has used a text editor before, but if you're confused, here is what everything is:

- The section on top is the tab bar. It displays the files that are currently open. If a file has been modified, a dot will be present next to its name.
- The section in the center is the editor window. It displays the content of the file that you are currently editing (nothing, in this example).
- The section at the bottom is the status bar. It normally displays information about the file that is open as well as the current mode (insert vs. replace), however its contents may change to display messages or prompt for input/confirmation.

### Key Bindings

| Keys               | Action                                   |
| ------------------ | ---------------------------------------- |
| `↑`, `↓`, `←`, `→` | Moves the cursor                         |
| `home`, `end`      | Moves the cursor to the beginning or the end of the line |
| `insert`           | Toggles between `INSERT` and `REPLACE` mode |
| `CTRL` + `n`       | Opens a new file                         |
| `CTRL` + `o`       | Opens an existing file                   |
| `CTRL` + `s`       | Saves the current file if it is modified (saves as if `SHIFT` is pressed) |
| `CTRL` + `w`       | Closes the current file                  |
| `CTRL` + `q`       | Closes all open files and quits the program |
| `CTRL` + `b`       | Jumps to the declaration under the cursor (works with library declarations & warps). |
| `CTRL` + `TAB`     | Cycles to the next tab                   |

> **Note:** Some of these actions may be unavailable while a prompt is showing. To exit a prompt, press backspace when there is no text in the buffer, or press `ESC` (only works in emulators).

**For advanced computers:**

- Use the scroll wheel to scroll up and down in the editor (or side-to-side by holding `SHIFT`).
- Holding `CTRL` and scrolling switches between open files.
- Scrolling the mouse while hovering on the tab bar lets you view tabs which don't fit on the screen.