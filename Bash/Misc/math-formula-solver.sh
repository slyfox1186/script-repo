#!/usr/bin/env bash

while true; do
    echo
    echo "Math Formula Solver"
    echo "======================="
    echo
    echo "This script provides a collection of math formulas for solving various problems."
    echo "Choose a formula from the list below by entering the corresponding number."
    echo
    echo "Available Formulas:"
    echo
    echo "Percentage Calculations:"
    echo "1) Calculate a percentage of a number"
    echo "2) Calculate the original price before a percentage increase"
    echo "3) Calculate percentage change"
    echo "4) Calculate percentage profit or loss"
    echo "5) Calculate percentage increase"
    echo "6) Calculate percentage decrease"
    echo "7) Calculate percentage difference"
    echo "8) Calculate percentage of a population growth"
    echo "9) Calculate percentage of a discount"
    echo "10) Increase a number by a percentage"
    echo
    echo "Geometric Calculations:"
    echo "11) Pythagorean Theorem"
    echo "12) Area of a Circle"
    echo "13) Volume of a Sphere"
    echo "14) Slope of a Line"
    echo "15) Midpoint of a Line Segment"
    echo "16) Area of a Triangle (using base and height)"
    echo "17) Circumference of a Circle"
    echo "18) Area of a Rectangle"
    echo "19) Volume of a Cylinder"
    echo
    echo "Algebraic Calculations:"
    echo "20) Quadratic Formula"
    echo "21) Linear Equation (Slope-Intercept Form)"
    echo "22) Linear Equation (Point-Slope Form)"
    echo "23) Arithmetic Sequence (nth term)"
    echo "24) Geometric Sequence (nth term)"
    echo "25) Binomial Expansion"
    echo
    read -p "Enter the formula number you want to use (or 'q' to quit): " formula
    clear

    if [[ "$formula" == "q" || "$formula" == "Q" ]]; then
        echo "Thank you for using the Math Formula Solver. Goodbye!"
        break
    fi

    case "$formula" in
        1)
            while true; do
                echo "Formula: Calculate a percentage of a number"
                echo "Values needed:"
                echo "- Number: The base number"
                echo "- Percentage: The percentage to calculate (without the % sign)"
                echo
                read -p "Enter the number: " number
                read -p "Enter the percentage (without % sign): " percentage
                if [[ -z "$number" || -z "$percentage" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                echo
                result=$(echo "scale=4; $number * $percentage / 100" | bc)
                echo "Input values:"
                echo "Number: $number"
                echo "Percentage: $percentage%"
                echo "Result: $result"
                break
            done
            ;;
        2)
            while true; do
                echo "Formula: Calculate the original price before a percentage increase"
                echo "Values needed:"
                echo "- Increased Price: The price after the increase"
                echo "- Increase Percentage: The percentage of the increase (without the % sign)"
                echo
                read -p "Enter the increased price: " increased_price
                read -p "Enter the increase percentage (without % sign): " increase_percentage
                if [[ -z "$increased_price" || -z "$increase_percentage" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; $increased_price / (1 + $increase_percentage / 100)" | bc)
                echo
                echo "Input values:"
                echo "Increased price: $increased_price"
                echo "Increase percentage: $increase_percentage%"
                echo "Original price: $result"
                break
            done
            ;;
        3)
            while true; do
                echo "Formula: Calculate percentage change"
                echo "Values needed:"
                echo "- Original Number: The initial value"
                echo "- New Number: The new value"
                echo
                read -p "Enter the original number: " original
                read -p "Enter the new number: " new
                if [[ -z "$original" || -z "$new" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; ($new - $original) / $original * 100" | bc)
                echo
                echo "Input values:"
                echo "Original number: $original"
                echo "New number: $new"
                echo "Percentage change: $result%"
                break
            done
            ;;
        4)
            while true; do
                echo "Formula: Calculate percentage profit or loss"
                echo "Values needed:"
                echo "- Cost: The cost of the item"
                echo "- Selling Price: The selling price of the item"
                echo
                read -p "Enter the cost: " cost
                read -p "Enter the selling price: " selling_price
                if [[ -z "$cost" || -z "$selling_price" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                if (( $(echo "$selling_price > $cost" | bc -l) )); then
                    result=$(echo "scale=4; ($selling_price - $cost) / $cost * 100" | bc)
                    echo
                    echo "Input values:"
                    echo "Cost: $cost"
                    echo "Selling price: $selling_price"
                    echo "Percentage profit: $result%"
                else
                    result=$(echo "scale=4; ($cost - $selling_price) / $cost * 100" | bc)
                    echo
                    echo "Input values:"
                    echo "Cost: $cost"
                    echo "Selling price: $selling_price"
                    echo "Percentage loss: $result%"
                fi
                break
            done
            ;;
        5)
            while true; do
                echo "Formula: Calculate percentage increase"
                echo "Values needed:"
                echo "- Original Number: The initial value"
                echo "- Increased Number: The increased value"
                echo
                read -p "Enter the original number: " original
                read -p "Enter the increased number: " increased
                if [[ -z "$original" || -z "$increased" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; ($increased - $original) / $original * 100" | bc)
                echo
                echo "Input values:"
                echo "Original number: $original"
                echo "Increased number: $increased"
                echo "Percentage increase: $result%"
                break
            done
            ;;
        6)
            while true; do
                echo "Formula: Calculate percentage decrease"
                echo "Values needed:"
                echo "- Original Number: The initial value"
                echo "- Decreased Number: The decreased value"
                echo
                read -p "Enter the original number: " original
                read -p "Enter the decreased number: " decreased
                if [[ -z "$original" || -z "$decreased" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; ($original - $decreased) / $original * 100" | bc)
                echo
                echo "Input values:"
                echo "Original number: $original"
                echo "Decreased number: $decreased"
                echo "Percentage decrease: $result%"
                break
            done
            ;;
        7)
            while true; do
                echo "Formula: Calculate percentage difference"
                echo "Values needed:"
                echo "- First Number: The first value"
                echo "- Second Number: The second value"
                echo
                read -p "Enter the first number: " first
                read -p "Enter the second number: " second
                if [[ -z "$first" || -z "$second" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; ($first - $second) / (($first + $second) / 2) * 100" | bc)
                echo
                echo "Input values:"
                echo "First number: $first"
                echo "Second number: $second"
                echo "Percentage difference: $result%"
                break
            done
            ;;
        8)
            while true; do
                echo "Formula: Calculate percentage of a population growth"
                echo "Values needed:"
                echo "- Initial Population: The initial population size"
                echo "- Current Population: The current population size"
                echo
                read -p "Enter the initial population: " initial
                read -p "Enter the current population: " current
                if [[ -z "$initial" || -z "$current" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; ($current - $initial) / $initial * 100" | bc)
                echo
                echo "Input values:"
                echo "Initial population: $initial"
                echo "Current population: $current"
                echo "Percentage of population growth: $result%"
                break
            done
            ;;
        9)
            while true; do
                echo "Formula: Calculate percentage of a discount"
                echo "Values needed:"
                echo "- Original Price: The original price of the item"
                echo "- Discounted Price: The discounted price of the item"
                echo
                read -p "Enter the original price: " original_price
                read -p "Enter the discounted price: " discounted_price
                if [[ -z "$original_price" || -z "$discounted_price" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; ($original_price - $discounted_price) / $original_price * 100" | bc)
                echo
                echo "Input values:"
                echo "Original price: $original_price"
                echo "Discounted price: $discounted_price"
                echo "Percentage of the discount: $result%"
                break
            done
            ;;
        10)
            while true; do
                echo "Formula: Increase a number by a percentage"
                echo "Values needed:"
                echo "- Base Number: The number to be increased"
                echo "- Percentage: The percentage to increase the base number by (without the % sign)"
                echo
                read -p "Enter the base number: " base
                read -p "Enter the percentage (without % sign): " percentage
                if [[ -z "$base" || -z "$percentage" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; $base * (1 + $percentage / 100)" | bc)
                echo
                echo "Input values:"
                echo "Base number: $base"
                echo "Percentage: $percentage%"
                echo "Increased number: $result"
                break
            done
            ;;
        11)
            while true; do
                echo "Equation: Pythagorean Theorem (a^2 + b^2 = c^2)"
                echo "Values needed:"
                echo "- a: Length of one side of the right triangle"
                echo "- b: Length of the other side of the right triangle"
                echo
                read -p "Enter the length of side a: " a
                read -p "Enter the length of side b: " b
                if [[ -z "$a" || -z "$b" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; sqrt($a^2 + $b^2)" | bc)
                echo
                echo "Input values:"
                echo "Side a: $a"
                echo "Side b: $b"
                echo "Length of the hypotenuse (c): $result"
                break
            done
            ;;
        12)
            while true; do
                echo "Equation: Area of a Circle (A = πr^2)"
                echo "Values needed:"
                echo "- r: Radius of the circle"
                echo
                read -p "Enter the radius of the circle: " radius
                if [[ -z "$radius" ]]; then
                    echo "Please provide the required input."
                    echo
                    continue
                fi
                result=$(echo "scale=4; 3.14159 * $radius^2" | bc)
                echo
                echo "Input values:"
                echo "Radius: $radius"
                echo "Area of the circle: $result"
                break
            done
            ;;
        13)
            while true; do
                echo "Equation: Volume of a Sphere (V = (4/3)πr^3)"
                echo "Values needed:"
                echo "- r: Radius of the sphere"
                echo
                read -p "Enter the radius of the sphere: " radius
                if [[ -z "$radius" ]]; then
                    echo "Please provide the required input."
                    echo
                    continue
                fi
                result=$(echo "scale=4; (4/3) * 3.14159 * $radius^3" | bc)
                echo
                echo "Input values:"
                echo "Radius: $radius"
                echo "Volume of the sphere: $result"
                break
            done
            ;;
        14)
            while true; do
                echo "Equation: Slope of a Line (m = (y2 - y1) / (x2 - x1))"
                echo "Values needed:"
                echo "- x1: x-coordinate of the first point"
                echo "- y1: y-coordinate of the first point"
                echo "- x2: x-coordinate of the second point"
                echo "- y2: y-coordinate of the second point"
                echo
                read -p "Enter the x-coordinate of the first point (x1): " x1
                read -p "Enter the y-coordinate of the first point (y1): " y1
                read -p "Enter the x-coordinate of the second point (x2): " x2
                read -p "Enter the y-coordinate of the second point (y2): " y2
                if [[ -z "$x1" || -z "$y1" || -z "$x2" || -z "$y2" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; ($y2 - $y1) / ($x2 - $x1)" | bc)
                echo
                echo "Input values:"
                echo "Point 1: ($x1, $y1)"
                echo "Point 2: ($x2, $y2)"
                echo "Slope of the line: $result"
                break
            done
            ;;
        15)
            while true; do
echo "Equation: Midpoint of a Line Segment ((x1 + x2) / 2, (y1 + y2) / 2)"
                echo "Values needed:"
                echo "- x1: x-coordinate of the first endpoint"
                echo "- y1: y-coordinate of the first endpoint"
                echo "- x2: x-coordinate of the second endpoint"
                echo "- y2: y-coordinate of the second endpoint"
                echo
                read -p "Enter the x-coordinate of the first endpoint (x1): " x1
                read -p "Enter the y-coordinate of the first endpoint (y1): " y1
                read -p "Enter the x-coordinate of the second endpoint (x2): " x2
                read -p "Enter the y-coordinate of the second endpoint (y2): " y2
                if [[ -z "$x1" || -z "$y1" || -z "$x2" || -z "$y2" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                midpoint_x=$(echo "scale=4; ($x1 + $x2) / 2" | bc)
                midpoint_y=$(echo "scale=4; ($y1 + $y2) / 2" | bc)
                echo
                echo "Input values:"
                echo "Endpoint 1: ($x1, $y1)"
                echo "Endpoint 2: ($x2, $y2)"
                echo "Midpoint of the line segment: ($midpoint_x, $midpoint_y)"
                break
            done
            ;;
        16)
            while true; do
                echo "Equation: Area of a Triangle (A = (1/2) * base * height)"
                echo "Values needed:"
                echo "- base: Length of the base of the triangle"
                echo "- height: Height of the triangle"
                echo
                read -p "Enter the length of the base: " base
                read -p "Enter the height of the triangle: " height
                if [[ -z "$base" || -z "$height" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; 0.5 * $base * $height" | bc)
                echo
                echo "Input values:"
                echo "Base: $base"
                echo "Height: $height"
                echo "Area of the triangle: $result"
                break
            done
            ;;
        17)
            while true; do
                echo "Equation: Circumference of a Circle (C = 2πr)"
                echo "Values needed:"
                echo "- r: Radius of the circle"
                echo
                read -p "Enter the radius of the circle: " radius
                if [[ -z "$radius" ]]; then
                    echo "Please provide the required input."
                    echo
                    continue
                fi
                result=$(echo "scale=4; 2 * 3.14159 * $radius" | bc)
                echo
                echo "Input values:"
                echo "Radius: $radius"
                echo "Circumference of the circle: $result"
                break
            done
            ;;
        18)
            while true; do
                echo "Equation: Area of a Rectangle (A = length * width)"
                echo "Values needed:"
                echo "- length: Length of the rectangle"
                echo "- width: Width of the rectangle"
                echo
                read -p "Enter the length of the rectangle: " length
                read -p "Enter the width of the rectangle: " width
                if [[ -z "$length" || -z "$width" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; $length * $width" | bc)
                echo
                echo "Input values:"
                echo "Length: $length"
                echo "Width: $width"
                echo "Area of the rectangle: $result"
                break
            done
            ;;
        19)
            while true; do
                echo "Equation: Volume of a Cylinder (V = πr^2h)"
                echo "Values needed:"
                echo "- r: Radius of the base of the cylinder"
                echo "- h: Height of the cylinder"
                echo
                read -p "Enter the radius of the base: " radius
                read -p "Enter the height of the cylinder: " height
                if [[ -z "$radius" || -z "$height" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; 3.14159 * $radius^2 * $height" | bc)
                echo
                echo "Input values:"
                echo "Radius: $radius"
                echo "Height: $height"
                echo "Volume of the cylinder: $result"
                break
            done
            ;;
        20)
            while true; do
                echo "Equation: Quadratic Formula (x = (-b ± √(b^2 - 4ac)) / (2a))"
                echo "Values needed:"
                echo "- a: Coefficient of x^2"
                echo "- b: Coefficient of x"
                echo "- c: Constant term"
                echo
                read -p "Enter the coefficient of x^2 (a): " a
                read -p "Enter the coefficient of x (b): " b
                read -p "Enter the constant term (c): " c
                if [[ -z "$a" || -z "$b" || -z "$c" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                discriminant=$(echo "$b^2 - 4*$a*$c" | bc)
                if (( $(echo "$discriminant >= 0" | bc -l) )); then
                    root1=$(echo "scale=4; (-$b + sqrt($discriminant)) / (2*$a)" | bc)
                    root2=$(echo "scale=4; (-$b - sqrt($discriminant)) / (2*$a)" | bc)
                    echo
                    echo "Input values:"
                    echo "a: $a"
                    echo "b: $b"
                    echo "c: $c"
                    echo "Roots of the quadratic equation:"
                    echo "x1 = $root1"
                    echo "x2 = $root2"
                else
                    echo
                    echo "Input values:"
                    echo "a: $a"
                    echo "b: $b"
                    echo "c: $c"
                    echo "The quadratic equation has no real roots (discriminant < 0)."
                fi
                break
            done
            ;;
        21)
            while true; do
                echo "Formula: Linear Equation (Slope-Intercept Form) (y = mx + b)"
                echo "Values needed:"
                echo "- m: Slope of the line"
                echo "- b: y-intercept of the line"
                echo "- x: x-coordinate of a point on the line"
                echo
                read -p "Enter the slope (m): " m
                read -p "Enter the y-intercept (b): " b
                read -p "Enter the x-coordinate (x): " x
                if [[ -z "$m" || -z "$b" || -z "$x" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; $m * $x + $b" | bc)
                echo
                echo "Input values:"
                echo "Slope (m): $m"
                echo "y-intercept (b): $b"
                echo "x-coordinate (x): $x"
                echo "y-coordinate: $result"
                break
            done
            ;;
        22)
            while true; do
                echo "Formula: Linear Equation (Point-Slope Form) (y - y1 = m(x - x1))"
                echo "Values needed:"
                echo "- x1: x-coordinate of a known point"
                echo "- y1: y-coordinate of a known point"
                echo "- m: Slope of the line"
                echo "- x: x-coordinate of a point on the line"
                echo
                read -p "Enter the x-coordinate of the known point (x1): " x1
                read -p "Enter the y-coordinate of the known point (y1): " y1
                read -p "Enter the slope (m): " m
                read -p "Enter the x-coordinate (x): " x
                if [[ -z "$x1" || -z "$y1" || -z "$m" || -z "$x" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; $y1 + $m * ($x - $x1)" | bc)
                echo
                echo "Input values:"
                echo "Known point (x1, y1): ($x1, $y1)"
                echo "Slope (m): $m"
                echo "x-coordinate (x): $x"
                echo "y-coordinate: $result"
                break
            done
            ;;
        23)
            while true; do
                echo "Formula: Arithmetic Sequence (nth term) (an = a1 + (n - 1)d)"
                echo "Values needed:"
                echo "- a1: First term of the sequence"
                echo "- d: Common difference between terms"
                echo "- n: Position of the term to find"
                echo
                read -p "Enter the first term (a1): " a1
                read -p "Enter the common difference (d): " d
                read -p "Enter the position of the term to find (n): " n
                if [[ -z "$a1" || -z "$d" || -z "$n" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; $a1 + ($n - 1) * $d" | bc)
                echo
                echo "Input values:"
                echo "First term (a1): $a1"
                echo "Common difference (d): $d"
                echo "Position (n): $n"
                echo "Term at position $n: $result"
                break
            done
            ;;
        24)
            while true; do
                echo "Formula: Geometric Sequence (nth term) (an = a1 * r^(n-1))"
                echo "Values needed:"
                echo "- a1: First term of the sequence"
                echo "- r: Common ratio between terms"
                echo "- n: Position of the term to find"
                echo
                read -p "Enter the first term (a1): " a1
                read -p "Enter the common ratio (r): " r
                read -p "Enter the position of the term to find (n): " n
                if [[ -z "$a1" || -z "$r" || -z "$n" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                result=$(echo "scale=4; $a1 * e(l($r) * ($n - 1))" | bc -l)
                echo
                echo "Input values:"
                echo "First term (a1): $a1"
                echo "Common ratio (r): $r"
                echo "Position (n): $n"
                echo "Term at position $n: $result"
                break
            done
            ;;
        25)
            while true; do
                echo "Formula: Binomial Expansion ((a + b)^n)"
                echo "Values needed:"
                echo "- a: First term of the binomial"
                echo "- b: Second term of the binomial"
                echo "- n: Exponent of the binomial"
                echo
                read -p "Enter the first term (a): " a
                read -p "Enter the second term (b): " b
                read -p "Enter the exponent (n): " n
                if [[ -z "$a" || -z "$b" || -z "$n" ]]; then
                    echo "Please provide all the required inputs."
                    echo
                    continue
                fi
                echo
                echo "Input values:"
                echo "First term (a): $a"
                echo "Second term (b): $b"
                echo "Exponent (n): $n"
                echo "Binomial expansion: "
                for ((i=0; i<=n; i++))
                do
                    coeff=$(echo "scale=0; ($n - $i + 1) / $i" | bc)
                    term=$(echo "scale=4; $coeff * $a^($n-$i) * $b^$i" | bc)
                    if [ $i -eq 0 ]; then
                        printf "%s" "$term"
                    else
                        printf " + %s" "$term"
                    fi
                done
                echo
                break
            done
            ;;
        *)
            echo "Invalid formula number. Please select a valid formula from the list."
            ;;
    esac
done
