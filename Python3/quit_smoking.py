#!/usr/bin/env python3

from flask import Flask, request, render_template_string, abort
from datetime import datetime, timedelta
import argparse
import sys
import math
import re
from functools import lru_cache
from math import ceil

app = Flask(__name__)

def format_money(amount):
    return f"${amount:,.2f}"

def parse_arguments():
    parser = argparse.ArgumentParser(description='Quit Smoking Tracker Web Application')
    parser.add_argument('--host', default='127.0.0.1', help='Host to run the server on (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=5000, help='Port to run the server on (default: 5000)')
    parser.add_argument('--debug', action='store_true', help='Run in debug mode')
    return parser.parse_args()

INTERVALS = (
    ('weeks', 604800),
    ('days', 86400),
    ('hours', 3600),
    ('minutes', 60),
    ('seconds', 1),
)

@lru_cache(maxsize=1000)
def display_time(seconds, granularity=2):
    result = []
    for name, count in INTERVALS:
        value = seconds // count
        if value:
            seconds -= value * count
            if value == 1:
                name = name.rstrip('s')
            result.append(f"{int(value)} {name}")
    return ', '.join(result[:granularity])

BENEFITS = [
    (600, '10 minutes: Your heart rate drops'),
    (1200, '20 minutes: Your resting heart rate has already reduced (this is a key indicator of your overall fitness level)'),
    (28800, '8 hours: Nicotine in your system has halved'),
    (43200, '12 hours: The carbon monoxide level in your blood has decreased dramatically, oxygen levels in your blood have improved, and the carbon monoxide level in your blood drops to normal'),
    (86400, '24 hours: The nicotine level in your blood drops to a negligible amount'),
    (172800, '48 hours: All carbon monoxide is flushed out. Your lungs are clearing out mucus, your senses of taste and smell are improving, and previously damaged nerve endings start to regrow'),
    (259200, '72 hours: Breathing feels easier as your bronchial tubes have started to relax. Your energy is increasing, and your lung capacity (the ability of the lungs to fill up with air) is improving'),
    (604800, '7 days: After a week without smoking, the carbon monoxide in your blood drops to normal levels'),
    (1209600, '2 weeks: You now have a lower risk of heart attack'),
    (2419200, '1 month: You now cough less and have fewer instances of shortness of breath'),
    (31536000, '1 year: Your risk of coronary heart disease is now about half that of someone who continues to smoke'),
    (157680000, '5 years: Your risk of cancers of the mouth, throat, and voice box drops by half'),
    (315360000, '10 years: Your risk of death from lung cancer will have halved compared with a smoker\'s'),
    (473040000, '15 years: Your risk of coronary heart disease drops to close to that of someone who does not smoke'),
    (630720000, '20 years: Your risk of heart attack and stroke will be similar to that of someone who has never smoked')
]

SUGGESTED_PURCHASES = [
    (10, "A movie ticket"),
    (20, "A takeaway meal"),
    (50, "A nice dinner at a restaurant"),
    (100, "A new item of clothing"),
    (200, "A new gadget or electronics accessory"),
    (500, "A weekend getaway"),
    (1000, "A new smartphone or tablet"),
    (2000, "A high-end computer or gaming console"),
    (5000, "A luxury vacation"),
    (10000, "A used car or major home renovation")
]

# Update this list to use formatted money values
SUGGESTED_PURCHASES = [(amount, f"{item} ({format_money(amount)})") for amount, item in SUGGESTED_PURCHASES]

HTML_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Quit Smoking Progress</title>
    <style>
        body { font-family: Verdana, sans-serif; line-height: 1.6; margin: 20px; background-color: #1e1e1e; color: #ffffff; }
        .container { max-width: 95%; margin: 0 auto; text-align: left; }
        .stats { font-size: 26px; margin-bottom: 20px; }
        .milestones, .purchases { font-size: 22px; margin-bottom: 20px; }
        .benefits { margin: 20px 0; }
        h1, h2 { margin-bottom: 10px; }
        ul { padding-left: 20px; }
        .save-more { color: #3498DB; }
        .purchase-item { color: #25F969; }
        .important-word { color: #FF5733; }
        .time-left-label { color: #FFFF00; }
        .time-left-value { color: #FFFFFF; }
        .time-interval { color: #25F969; font-weight: bold; }
        .benefit-description { color: #FFD700; }
        .progress-title { color: #FF6B6B; font-size: 32px; font-weight: bold; }
        .quit-date { color: #FFFF00; }
        .time-quit { color: #45B7D1; font-weight: bold; }
        .money-saved { color: #00A738; font-weight: bold; }
    </style>
    <script>
        function updateTime() {
            const quitDate = new Date({{ year }}, {{ month - 1 }}, {{ day }}, 9, 0, 0);
            const now = new Date();
            const diff = Math.floor((now - quitDate) / 1000);
            
            const weeks = Math.floor(diff / 604800);
            const days = Math.floor((diff % 604800) / 86400);
            const hours = Math.floor((diff % 86400) / 3600);
            const minutes = Math.floor((diff % 3600) / 60);
            const seconds = diff % 60;
            
            let timeString = '';
            if (weeks > 0) timeString += weeks + (weeks === 1 ? ' week, ' : ' weeks, ');
            if (days > 0) timeString += days + (days === 1 ? ' day, ' : ' days, ');
            if (hours > 0) timeString += hours + (hours === 1 ? ' hour, ' : ' hours, ');
            if (minutes > 0) timeString += minutes + (minutes === 1 ? ' minute, ' : ' minutes, ');
            timeString += seconds + (seconds === 1 ? ' second' : ' seconds');
            
            document.getElementById('time-quit').textContent = timeString;
            
            const totalSaved = (diff * {{ saved_per_second }}).toFixed(2);
            document.getElementById('money-saved').textContent = '$' + numberWithCommas(totalSaved);
        }
        
        function numberWithCommas(x) {
            return x.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        }
        
        setInterval(updateTime, 1000);
    </script>
</head>
<body onload="updateTime()">
    <div class="container">
        <h1 class="progress-title">Quit Smoking Progress</h1>
        <div class="stats">
            Quit Date: <span class="quit-date">{{ month }}/{{ day }}/{{ year }} 9:00 AM</span><br>
            Time Quit: <span class="time-quit"><span id="time-quit"></span></span><br>
            Money Saved: <span class="money-saved"><span id="money-saved"></span></span>
        </div>
        
        <div class="purchases">
            <h2>Suggested purchases based on your savings:</h2>
            <ul>
            {% for amount, item in suggested_purchases %}
                {% if total_saved >= amount %}
                    <li><span class="purchase-item">{{ item }}</span></li>
                {% else %}
                    {% set money_needed = (amount - total_saved) | round(2) %}
                    {% set days_left = ceil(money_needed / saved_per_day) %}
                    {% set time_left = display_time(days_left * 24 * 60 * 60, 2) %}
                    <li><span class="purchase-item">{{ item }}</span> - <span class="save-more">Save {{ format_money(money_needed) }} more</span> <span class="time-left">(about {{ time_left }} left)</span></li>
                {% endif %}
            {% endfor %}
            </ul>
        </div>
        
        <div class="benefits">
            <h2>Health benefits:</h2>
            <h3>Achieved benefits:</h3>
            <ul>
            {% for seconds, desc in achieved_benefits %}
                <li><span class="time-interval">{{ desc.split(':')[0] }}:</span> {{ desc.split(':', 1)[1] | safe }}</li>
            {% endfor %}
            </ul>
            
            <h3>Upcoming benefits:</h3>
            <ul>
            {% for seconds, desc, time_left in upcoming_benefits %}
                <li>
                    <span class="time-interval">{{ desc.split(':')[0] }}:</span> {{ desc.split(':', 1)[1] | safe }}
                    <br>
                    <span class="time-left-label">Time left:</span> <span class="time-left-value">{{ time_left }}</span>
                </li>
            {% endfor %}
            </ul>
        </div>
        <p><a href="/help">Need help?</a></p>
    </div>
</body>
</html>
'''

@app.route('/quitsmoking', methods=['GET', 'POST'])
def page():
    try:
        month = int(request.args.get('month'))
        day = int(request.args.get('day'))
        year = int(request.args.get('year'))
        saved_per_day = float(request.args.get('saved-per-day'))
    except (TypeError, ValueError):
        return generate_input_page(datetime.now())

    quit_date = f"{month}-{day}-{year}"
    return generate_tracking_page(quit_date, saved_per_day)

def generate_input_page(now):
    date_options = ''.join(f'<option value="{(now - timedelta(days=i)).strftime("%m-%d-%Y")}">{(now - timedelta(days=i)).strftime("%m-%d-%Y")}</option>' for i in range(30))
    return f'''
    <html>
    <head>
        <title>Quit Smoking Tracker</title>
        <style>
            body {{ font-family: Arial, sans-serif; line-height: 1.6; margin: 40px; background-color: #1e1e1e; color: #ffffff; }}
            .container {{ max-width: 600px; margin: 0 auto; text-align: center; }}
            select, input[type="number"] {{ padding: 8px; margin: 5px; border-radius: 4px; border: 1px solid #ccc; }}
            input[type="submit"] {{ padding: 10px 20px; background-color: #4CAF50; color: white; border: none; border-radius: 5px; cursor: pointer; }}
            input[type="submit"]:hover {{ background-color: #45a049; }}
        </style>
    </head>
    <body>
        <div class="container">
            <h2>Quit Smoking Tracker</h2>
            <form action="/quitsmoking" method="get">
                <label for="quit-date">Quit date:</label><br>
                <select name="quit-date" id="quit-date" required>
                    {date_options}
                </select><br>
                <label for="saved-per-day">Money saved per day:</label><br>
                $<input type="number" name="saved-per-day" id="saved-per-day" step="0.01" required><br>
                <input type="submit" value="Track Progress">
            </form>
            <p><a href="/help">Need help?</a></p>
        </div>
    </body>
    </html>
    '''

def generate_tracking_page(quit_date, saved_per_day):
    try:
        month, day, year = map(int, quit_date.split("-"))
        quitdate_dt = datetime(year, month, day, 9, 0)
        current_dt = datetime.now()
        time_difference = current_dt - quitdate_dt
        quittime_seconds = time_difference.total_seconds()
        
        saved_per_second = saved_per_day / 24 / 60 / 60
        total_saved = round(saved_per_second * quittime_seconds, 2)
        
        achieved_benefits = []
        upcoming_benefits = []
        important_words = ["heart rate", "nicotine", "carbon monoxide", "oxygen levels", "nerve endings", "bronchial tubes", "lung capacity", "heart attack", "shortness of breath", "coronary heart disease", "cancers", "lung cancer"]
        
        for seconds, desc in BENEFITS:
            highlighted_desc = desc
            for word in important_words:
                highlighted_desc = highlighted_desc.replace(word, f"<span class='important-word'>{word}</span>")
            if quittime_seconds >= seconds:
                achieved_benefits.append((seconds, highlighted_desc))
                app.logger.debug(f"Achieved Benefit: {highlighted_desc}")
            else:
                time_to_benefit = seconds - quittime_seconds
                time_left = display_time(int(time_to_benefit), 2)
                upcoming_benefits.append((seconds, highlighted_desc, time_left))
        
        app.logger.debug(f"Total Achieved Benefits: {len(achieved_benefits)}")
        app.logger.debug(f"Total Upcoming Benefits: {len(upcoming_benefits)}")
        
        return render_template_string(
            HTML_TEMPLATE,
            month=month,
            day=day,
            year=year,
            saved_per_second=saved_per_second,
            total_saved=total_saved,
            suggested_purchases=SUGGESTED_PURCHASES,
            saved_per_day=saved_per_day,
            display_time=display_time,
            achieved_benefits=achieved_benefits,
            upcoming_benefits=upcoming_benefits,
            ceil=ceil,
            format_money=format_money
        )
        
    except Exception as e:
        app.logger.error(f"Error processing tracking page: {str(e)}")
        abort(500, description="There was an error processing your information. Please try again.")

@app.route('/')
def home():
    now = datetime.now()
    month_options = ''.join([f'<option value="{i:02d}">{datetime(1900, i, 1).strftime("%B")}</option>' for i in range(1, 13)])
    day_options = ''.join([f'<option value="{i:02d}">{i:02d}</option>' for i in range(1, 32)])
    year_options = ''.join([f'<option value="{year}">{year}</option>' for year in range(now.year, now.year - 30, -1)])
    
    return render_template_string('''
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Quit Smoking Tracker</title>
        <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; margin: 40px; background-color: #1e1e1e; color: #ffffff; }
            .container { max-width: 600px; margin: 0 auto; text-align: center; }
            .btn { 
                display: inline-block;
                padding: 10px 20px;
                background-color: #4CAF50;
                color: white;
                text-decoration: none;
                border-radius: 5px;
                margin: 10px;
            }
            .btn:hover {
                background-color: #45a049;
            }
            select, input[type="number"] {
                padding: 8px;
                margin: 5px;
                border-radius: 4px;
                border: 1px solid #ccc;
                background-color: #2c2c2c;
                color: #ffffff;
            }
            form {
                margin-top: 20px;
            }
        </style>
        <script>
        function updateDays() {
            var month = document.getElementById('month').value;
            var year = document.getElementById('year').value;
            var day = document.getElementById('day');
            var days = new Date(year, month, 0).getDate();
            var currentDay = day.value;
            day.innerHTML = '';
            for (var i = 1; i <= days; i++) {
                var option = document.createElement('option');
                option.value = i.toString().padStart(2, '0');
                option.text = i.toString().padStart(2, '0');
                day.appendChild(option);
            }
            if (currentDay <= days) {
                day.value = currentDay;
            }
        }
        </script>
    </head>
    <body>
        <div class="container">
            <h1>Welcome to Quit Smoking Tracker</h1>
            <p>Take control of your health and track your progress in quitting smoking.</p>
            <form action="/quitsmoking" method="get">
                <label for="month">Quit Date:</label><br>
                <select id="month" name="month" onchange="updateDays()" required>
                    {{ month_options | safe }}
                </select>
                <select id="day" name="day" required>
                    {{ day_options | safe }}
                </select>
                <select id="year" name="year" onchange="updateDays()" required>
                    {{ year_options | safe }}
                </select><br>
                <input type="number" name="saved-per-day" placeholder="Money Saved Per Day ($)" step="0.01" required><br>
                <input type="submit" value="Start Tracking Now" class="btn">
            </form>
            <p>Current server date: {{ now.strftime('%m-%d-%Y') }}</p>
            <a href="/help" class="btn">View Help Guide</a>
        </div>
    </body>
    </html>
    ''', month_options=month_options, day_options=day_options, year_options=year_options, now=now)

if __name__ == '__main__':
    args = parse_arguments()
    try:
        app.run(host=args.host, port=args.port, debug=args.debug)
    except Exception as e:
        print(f"Error starting server: {e}", file=sys.stderr)
        sys.exit(1)
