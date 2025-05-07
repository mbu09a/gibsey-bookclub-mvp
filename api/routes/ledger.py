import pathlib
from fastapi import APIRouter, HTTPException, status
from fastapi.responses import FileResponse

# Import the main export function and the output path from your script
# Adjust the import path based on your project structure if scripts is not directly accessible
# For this structure, we assume scripts is a sibling of api, so we go up and then into scripts
# However, direct execution of scripts from API routes can be complex due to pathing and permissions.
# A better long-term solution might be a shared utility or a task queue if generation is slow.

# For now, let's define the path directly as the script does, relative to project root
# This router module is in api/routes/, so project_root is three levels up.
PROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
LEDGER_CSV_PATH = PROJECT_ROOT / "public" / "ledger.csv"

# To call the script's main function if the CSV is missing:
import sys
# Add scripts directory to path to allow import if it's not a package
scripts_dir = PROJECT_ROOT / "scripts"
sys.path.append(str(scripts_dir))

# Conditional import for the script's main function
try:
    from export_ledger import main as run_export_ledger_script
except ImportError as e:
    print(f"Could not import run_export_ledger_script from export_ledger.py: {e}")
    # Define a dummy function if import fails, so app can still start but feature will be broken
    def run_export_ledger_script():
        print("ERROR: export_ledger.py script could not be called to generate CSV.")
        # In a real app, you might raise an error or have more robust handling

router = APIRouter()

@router.get("/ledger.csv")
async def download_ledger_csv():
    """Serves the generated ledger.csv file. 
    If the file doesn't exist, it attempts to generate it on-demand."""
    
    if not LEDGER_CSV_PATH.exists():
        print(f"Ledger CSV not found at {LEDGER_CSV_PATH}, attempting to generate on-demand...")
        try:
            run_export_ledger_script() # Call the main function from your script
            if not LEDGER_CSV_PATH.exists(): # Check again after generation attempt
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, 
                    detail="Ledger CSV could not be generated on-demand."
                )
            print("Ledger CSV generated successfully on-demand.")
        except Exception as e:
            print(f"Error during on-demand CSV generation: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, 
                detail=f"Failed to generate ledger CSV on-demand: {e}"
            )

    return FileResponse(
        path=LEDGER_CSV_PATH,
        media_type="text/csv",
        filename="ledger.csv" # This suggests the download filename to the browser
    ) 