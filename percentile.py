import re

def estrai_metriche_istogramma(file_path):
    latenze = []
    totale_campioni = 0
    wcet_letto = None

    try:
        with open(file_path, 'r') as file:
            for linea in file:
                # Estrazione del Max Latency (WCET) dal riepilogo di cyclictest
                if "Max Latencies:" in linea:
                    match = re.search(r'Max Latencies:\s*(\d+)', linea, re.IGNORECASE)
                    if match:
                        wcet_letto = float(match.group(1))
                    continue

                # Ignora righe vuote o altri commenti
                if linea.strip() == "" or linea.startswith("#"):
                    continue
                
                # Parsing dei dati dell'istogramma (Colonna 1: Latenza, Colonna 2: Conteggio)
                parti = linea.split()
                if len(parti) >= 2:
                    try:
                        latenza = int(parti[0])
                        conteggio = int(parti[1])
                        
                        latenze.append((latenza, conteggio))
                        totale_campioni += conteggio
                    except ValueError:
                        continue
                        
        if totale_campioni == 0:
            print("[!] Nessun dato valido trovato nell'istogramma.")
            return None

        # Calcolo dei target per i percentili
        target_50 = totale_campioni * 0.50  # Mediana
        target_99 = totale_campioni * 0.99  # 99° Percentile
        
        somma_corrente = 0
        mediana = None
        percentile_99 = None
        
        # Scorre i dati ordinati per latenza per trovare le soglie
        latenze.sort(key=lambda x: x[0])
        
        for latenza, conteggio in latenze:
            somma_corrente += conteggio
            
            # Appena la somma progressiva supera il 50%, abbiamo trovato la mediana
            if mediana is None and somma_corrente >= target_50:
                mediana = latenza
                
            # Appena la somma progressiva supera il 99%, abbiamo trovato il 99° percentile
            if percentile_99 is None and somma_corrente >= target_99:
                percentile_99 = latenza
        
        # Se per qualche motivo il WCET non era nei commenti finali, 
        # prendi l'ultima latenza valida registrata nell'istogramma
        wcet = wcet_letto if wcet_letto is not None else latenze[-1][0]

        return {
            "campioni_totali": totale_campioni,
            "mediana": mediana,
            "percentile_99": percentile_99,
            "wcet": wcet
        }
                
    except FileNotFoundError:
        print(f"[!] Errore: Il file {file_path} non esiste.")
        return None

def main():
    print("=== ESTRATTORE METRICHE: MEDIANA, 99° PERCENTILE E WCET ===\n")
    
    file_log = input("Incolla il percorso del file di log dell'istogramma: ").strip().strip('"\'')

    print(f"\nAnalizzando l'istogramma in {file_log}...")
    
    metriche = estrai_metriche_istogramma(file_log)
    
    if metriche:
        print(f"\nRisultati dell'analisi su {metriche['campioni_totali']} campioni:")
        print("-" * 55)
        print(f"1. MEDIANA (50° Percentile):  {metriche['mediana']} µs")
        print(f"2. 99° PERCENTILE:            {metriche['percentile_99']} µs")
        print(f"3. WCET (Max Latency):        {int(metriche['wcet'])} µs")
        print("-" * 55)

if __name__ == "__main__":
    main()