#!/usr/bin/env bash

airules() {
    local text
    text="1. You must always remember that when writing condition statements with brackets you should use double brackets to enclose the text.
2. You must always remember that when using for loops you make the variable descriptive to the task at hand.
3. You must always remember that when inside of a bash function all variables must be declared on a single line at the top of the function without values, then you may write the variables with their values below this line but without the local command in the same line since you already did that on the first line without the values of the variables.
4. All arrays must conform to rule number 3 except in this case, you write the array name with an equal sign and empty parenthesis on the first line with a local command at the start of this line to initialize the array. Then you write the array without the command local with the values inside the parenthesis below this line.
5. You must always remember that you are never to edit any code inside a script unless it is required to fulfill my requests or instructions. Any other code unrelated to my request or instructions is never to be added to, modified, or removed in any way.
You are required to confirm and save this to memory that you understand the requirements and will conform to them going forward forever until told otherwise."

    echo "$text"
    if command -v xclip &>/dev/null; then
        echo "$text" | xclip -selection clipboard
    fi
    if command -v clip.exe &>/dev/null; then
        echo "$text" | clip.exe
    fi
}
