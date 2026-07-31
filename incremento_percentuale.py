import re
import math

def analizza_istogramma(file_path):
    """
    Legge l'istogramma, estrae il WCET e calcola Media e Deviazione Standard.
    """
    latenze = []
    totale_campioni = 0
    wcet_letto = None

    try:
        with open(file_path, 'r') as file:
            for linea in file:
                # Estrazione del WCET dal footer
                if "Max Latencies:" in linea:
                    match = re.search(r'Max Latencies:\s*(\d+)', linea, re.IGNORECASE)
                    if match:
                        wcet_letto = float(match.group(1))
                    continue

                if linea.strip() == "" or linea.startswith("#"):
                    continue
                
                parti = linea.split()
                if len(parti) >= 2:
                    try:
                        latenza = float(parti[0])
                        conteggio = int(parti[1])
                        
                        latenze.append((latenza, conteggio))
                        totale_campioni += conteggio
                    except ValueError:
                        continue
                        
        if totale_campioni == 0:
            return None

        # 1. Calcolo della Media
        somma_pesata = sum(latenza * conteggio for latenza, conteggio in latenze)
        media = somma_pesata / totale_campioni

        # 2. Calcolo della Varianza e Deviazione Standard
        somma_scarti_quadrati = sum(conteggio * ((latenza - media) ** 2) for latenza, conteggio in latenze)
        varianza = somma_scarti_quadrati / totale_campioni
        deviazione_standard = math.sqrt(varianza)
        
        # 3. WCET
        wcet = wcet_letto if wcet_letto is not None else latenze[-1][0]

        return {
            "media": media,
            "std_dev": deviazione_standard,
            "wcet": wcet
        }
                
    except FileNotFoundError:
        print(f"[!] Errore: Il file {file_path} non esiste.")
        return None

def calcola_incremento(valore_base, valore_stress):
    if valore_base == 0:
        return 0
    return ((valore_stress - valore_base) / valore_base) * 100

def main():
    print("=== ANALISI COMPLETA: MEDIA ± DEV. STANDARD E INCREMENTI ===\n")
    
    file_baseline = input("Incolla il percorso del log BASELINE: ").strip().strip('"\'')
    file_stress = input("Incolla il percorso del log SOTTO STRESS: ").strip().strip('"\'')

    print("\nElaborazione dei dati in corso...\n")
    
    dati_base = analizza_istogramma(file_baseline)
    dati_stress = analizza_istogramma(file_stress)
    
    if dati_base and dati_stress:
        # Formattazione Media +- StdDev
        str_media_base = f"{dati_base['media']:.2f} ± {dati_base['std_dev']:.2f} µs"
        str_media_stress = f"{dati_stress['media']:.2f} ± {dati_stress['std_dev']:.2f} µs"
        
        # Calcolo incrementi
        inc_media = calcola_incremento(dati_base['media'], dati_stress['media'])
        inc_wcet = calcola_incremento(dati_base['wcet'], dati_stress['wcet'])
        
        # Stampa dei risultati formattati per i docenti
        print("-" * 60)
        print(f"{'METRICA':<15} | {'BASELINE':<20} | {'STRESS WORKLOAD':<20}")
        print("-" * 60)
        print(f"{'Media ± SD':<15} | {str_media_base:<20} | {str_media_stress:<20}")
        print(f"{'WCET (Max)':<15} | {int(dati_base['wcet'])} µs{'':<16} | {int(dati_stress['wcet'])} µs")
        print("-" * 60)
        
        print("\n=> INCREMENTI PERCENTUALI (Stress rispetto a Baseline):")
        segno_media = "+" if inc_media > 0 else ""
        segno_wcet = "+" if inc_wcet > 0 else ""
        
        print(f"   • Incremento della Media: {segno_media}{inc_media:.2f}%")
        print(f"   • Incremento del WCET:    {segno_wcet}{inc_wcet:.2f}%")
        print("-" * 60)

if __name__ == "__main__":
    main()