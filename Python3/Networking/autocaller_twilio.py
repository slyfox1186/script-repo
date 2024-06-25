#!/usr/bin/env python3

from twilio.rest import Client
import time
import sys

# Twilio Account SID and Auth Token from your Twilio account
account_sid = '<ACCOUNT_SID_HERE>'
auth_token = '<AUTH_TOKEN_HERE>'

# Twilio phone number (purchased or verified on Twilio)
twilio_number = '<TWILIO_NUMBER_HERE>'

# Phone number to call (recipient's number)
to_number = '<NUMBER_TO_CALL_HERE>'

# Number of loops to execute (set to 'inf' for infinite loops)
MAX_LOOPS = 'inf'  # Set to 'inf' for infinite loops, or a number for a finite number of loops

# Sleep duration between each call (in seconds)
SLEEP_DURATION = 1  # Adjust as needed, e.g., 0.5 for half a second, 2 for two seconds, etc.

# Message to say during the call (multi-line text)
SAY_MESSAGE = """
This is an important message from your automated system.
Please listen carefully as we provide important information.
Thank you for your attention.
"""

# Function to initiate the call
def make_calls(max_loops):
    # Initialize Twilio client outside the loop
    client = Client(account_sid, auth_token)

    loop_count = 0

    try:
        while True:
            # Make a call using Twilio API with SAY_MESSAGE
            call = client.calls.create(
                twiml=f'<Response><Say>{SAY_MESSAGE}</Say></Response>',
                to=to_number,
                from_=twilio_number
            )

            print(f"Calling {to_number}... Call SID: {call.sid}")

            # Increment loop count
            loop_count += 1

            # Check if reached maximum loops
            if max_loops != 'inf' and loop_count >= int(max_loops):
                print(f"Reached maximum loops ({max_loops}). Stopping the autodialer.")
                break

            # Wait for specified duration before making the next call
            time.sleep(SLEEP_DURATION)

    except KeyboardInterrupt:
        print("\nStopping the autodialer.")
        sys.exit(0)
    except Exception as e:
        print(f"Error occurred: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    make_calls(MAX_LOOPS)
