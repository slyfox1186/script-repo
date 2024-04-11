#!/usr/bin/env python3

import math

# Dictionary of drugs and their half-lives in days
drug_half_lives = {
    "Marijuana": 7,
    "Cocaine": 0.7,
    "Heroin": 0.3,
    "Methamphetamine": 0.6,
    "d-Amphetamine": 0.5,
    "Clonazepam": 1.25,
    "Xanax": 0.6,
    "Diazepam": 2,
    "Lorazepam": 0.8,
    "Alprazolam": 0.6,
    "Midazolam": 0.3,
    "Opioids": 0.5,
    "Barbiturates": 1.1,
    "Methadone": 1.5,
    "LSD": 0.3
}

def get_detection_range(drug_type, dosage_per_pill, pills_per_day, duration_in_days):
    half_life = drug_half_lives[drug_type]

    total_dose = dosage_per_pill * pills_per_day * duration_in_days
    min_detection_time = 5 * half_life  # 5 half-lives to reach ~97% elimination
    max_detection_time = 5 * half_life * (1 + (total_dose / (dosage_per_pill * duration_in_days)))  # Accounting for higher dose

    return min_detection_time, max_detection_time

def calculate_mean_lifetime(half_life):
    # T = (ln(2)) / λ = τ ln(2)
    return half_life / math.log(2)

def main():
    print("Select the drug you took from the list below:")
    for i, drug in enumerate(drug_half_lives.keys(), start=1):
        print(f"{i}. {drug}")

    choice = int(input("Enter the number corresponding to your choice: "))
    drug_type = list(drug_half_lives.keys())[choice - 1]

    dosage_per_pill = float(input(f"Enter the dosage per pill (in mg) for {drug_type}: "))
    pills_per_day = int(input(f"Enter the number of {drug_type} pills you took per day: "))
    duration_in_days = int(input(f"Enter the number of days you took {drug_type}: "))

    min_detection_time, max_detection_time = get_detection_range(drug_type, dosage_per_pill, pills_per_day, duration_in_days)

    min_days = int(min_detection_time)
    min_hours = int((min_detection_time - min_days) * 24)
    max_days = int(max_detection_time)
    max_hours = int((max_detection_time - max_days) * 24)

    print(f"\nThe minimum time for {drug_type} to be undetectable in a urine test is approximately {min_days} days and {min_hours} hours.")
    print(f"The maximum time for {drug_type} to be undetectable in a urine test is approximately {max_days} days and {max_hours} hours.")

    # Calculate and display average detection time
    avg_detection_time = (min_detection_time + max_detection_time) / 2
    avg_days = int(avg_detection_time)
    avg_hours = int((avg_detection_time - avg_days) * 24)
    print(f"The average time for {drug_type} to be undetectable in a urine test is approximately {avg_days} days and {avg_hours} hours.")

    # Calculate and display mean lifetime
    half_life = drug_half_lives[drug_type]
    mean_lifetime = calculate_mean_lifetime(half_life)
    print(f"The mean lifetime (τ) for {drug_type} is approximately {mean_lifetime:.2f} days.")

if __name__ == "__main__":
    main()
