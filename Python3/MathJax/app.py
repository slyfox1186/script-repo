from flask import Flask, render_template, request, jsonify
from markupsafe import Markup, escape
import re
import sympy as sp
import traceback
import logging

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

def convert_to_latex(equation):
    logger.debug(f"Converting equation to LaTeX: {equation}")
    # Convert basic math operations to LaTeX
    conversions = [
        (r'(\d+)\s*/\s*(\d+)', r'\\frac{\1}{\2}'),
        (r'(\w+|\(.+?\))\^(\w+|\(.+?\))', r'{\1}^{\2}'),
        (r'(\d+|[a-zA-Z])\s*\*\s*(\d+|[a-zA-Z])', r'\1 \\times \2'),
        (r'sqrt\((.+?)\)', r'\\sqrt{\1}'),
        (r'cbrt\((.+?)\)', r'\\sqrt[3]{\1}'),
        (r'\bpi\b', r'\\pi'),
        (r'([a-zA-Z])_(\d+)', r'\1_{\2}'),
        (r'\b(sin|cos|tan|csc|sec|cot)\b', r'\\\1'),
        (r'\blog\b', r'\\log'),
        (r'\bln\b', r'\\ln'),
        (r'\|(.+?)\|', r'\\left|{\1}\\right|'),
        (r'\b(alpha|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|xi|omicron|pi|rho|sigma|tau|upsilon|phi|chi|psi|omega)\b', r'\\\1'),
        (r'\binf\b', r'\\infty'),
    ]
    
    for pattern, replacement in conversions:
        equation = re.sub(pattern, replacement, equation)
    
    if '=' in equation:
        left, right = equation.split('=', 1)
        equation = f"{left.strip()} = {right.strip()}"
    
    logger.debug(f"Converted equation: {equation}")
    return equation

def generate_steps(equation):
    logger.debug(f"Generating steps for equation: {equation}")
    steps = []
    try:
        expr_str = equation.replace('^', '**')
        expr_str = re.sub(r'(\d+)([a-zA-Z])', r'\1*\2', expr_str)
        logger.debug(f"Pre-processed expression: {expr_str}")

        local_dict = {'sqrt': sp.sqrt, 'cbrt': sp.cbrt}
        expr = sp.sympify(expr_str, locals=local_dict, evaluate=False)
        
        def add_step(step, is_main_step=False):
            if steps:
                last_step = steps[-1]
                if last_step == step:
                    if is_main_step:
                        # If a main step is identical to the previous, finalize the answer
                        steps.append(Markup("\\text{Final result:}"))
                        steps.append(step)
                        return False  # Stop processing further steps
                    else:
                        # If a sub-step is identical to the previous, skip it
                        return True  # Continue processing
            steps.append(step)
            return True  # Continue processing

        # Step 1
        if not add_step(Markup("\\text{Step 1: Identify the expression}"), True):
            return steps
        if not add_step(Markup(sp.latex(expr)), True):
            return steps

        # Step 2: Simplify square roots
        if expr.has(sp.sqrt):
            if not add_step(Markup("\\text{Step 2: Simplify square roots}"), True):
                return steps
            simplified_sqrt = expr.subs([(sp.sqrt(n), sp.sqrt(n).evalf()) for n in expr.atoms(sp.Number) if sp.sqrt(n).is_rational])
            if not add_step(Markup(sp.latex(simplified_sqrt))):
                return steps
            expr = simplified_sqrt

        if expr.has(sp.Pow):
            if not add_step(Markup(f"\\text{{Step 3: Evaluate powers}}"), True):
                return steps
            power_atoms = list(expr.atoms(sp.Pow))
            for i, pow_expr in enumerate(power_atoms, 1):
                base, exp = pow_expr.as_base_exp()
                step_text = f"\\text{{3.{i}: Evaluate }} {sp.latex(base)}^{{{sp.latex(exp)}}}"
                if not add_step(Markup(step_text)):
                    return steps
                evaluated_power = pow_expr.evalf()
                if not add_step(Markup(f"{sp.latex(base)}^{{{sp.latex(exp)}}} = {sp.latex(evaluated_power)}")):
                    return steps
            evaluated_powers = expr.subs([(pow_expr, pow_expr.evalf()) for pow_expr in power_atoms])
            if not add_step(Markup(f"{sp.latex(evaluated_powers)}")):
                return steps
            expr = evaluated_powers

        if not add_step(Markup(f"\\text{{Step 4: Perform arithmetic}}"), True):
            return steps
        final_result = expr.evalf()
        if not add_step(Markup(f"{sp.latex(final_result)}")):
            return steps

        if not add_step(Markup(f"\\text{{Step 5: Simplify the result}}"), True):
            return steps
        simplified_result = sp.simplify(final_result)
        if simplified_result != final_result:
            if not add_step(Markup(f"{sp.latex(simplified_result)}")):
                return steps

        add_step(Markup(f"\\text{{Final result:}}"))
        add_step(Markup(f"{sp.latex(simplified_result)}"))

    except sp.SympifyError as e:
        logger.error(f"SympifyError occurred: {str(e)}")
        logger.error(traceback.format_exc())
        steps.append(Markup(f"\\text{{Error: Unable to parse the expression. {escape(str(e))}}}"))
    except Exception as e:
        logger.error(f"Unexpected error occurred: {str(e)}")
        logger.error(traceback.format_exc())
        steps.append(Markup(f"\\text{{Error: Unable to generate steps. {escape(str(e))}}}"))

    logger.debug(f"Generated steps: {steps}")
    return steps

@app.route('/')
def index():
    logger.info("Rendering index page")
    return render_template('index.html')

@app.route('/render', methods=['POST'])
def render_equation():
    logger.info("Received request to render equation")
    equation = request.json.get('equation', '')
    logger.debug(f"Original equation: {equation}")
    
    try:
        latex_equation = convert_to_latex(equation)
        logger.debug(f"LaTeX equation: {latex_equation}")
        
        steps = generate_steps(equation)
        logger.debug(f"Generated steps: {steps}")
        
        response = jsonify({
            'latex': latex_equation,
            'steps': steps
        })
        logger.info("Successfully rendered equation and generated steps")
        return response
    except Exception as e:
        logger.error(f"Error processing equation: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({'error': f"Error processing equation: {str(e)}"}), 400

if __name__ == '__main__':
    logger.info("Starting Flask application")
    app.run(debug=True)