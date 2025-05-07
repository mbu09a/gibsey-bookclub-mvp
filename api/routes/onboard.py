import pathlib
import markdown # For converting Markdown to HTML
from fastapi import APIRouter, Request, HTTPException, status
from fastapi.responses import HTMLResponse, RedirectResponse

router = APIRouter()

# Define project root assuming this script is in api/routes/
PROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
ONBOARDING_MD_PATH = PROJECT_ROOT / "docs" / "onboarding.md"

# Path for the Tailwind CDN, can be centralized later if used in multiple HTML responses
TAILWIND_CDN_URL = "https://cdn.tailwindcss.com?plugins=typography"

@router.get("/welcome", response_class=HTMLResponse)
async def welcome_page(request: Request):
    """Serves the onboarding.md content as a styled HTML page."""
    try:
        markdown_content = ONBOARDING_MD_PATH.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise HTTPException(status_code=500, detail="Onboarding markdown file not found.")
    
    html_body = markdown.markdown(markdown_content)
    
    # Adjusted form action to be relative to the router's prefix + /welcome
    # If router is at /api/v1/onboard, action becomes "../enter" if /enter is at /api/v1/onboard/enter
    # Simpler: define /enter at the root of this router, so action is just "./enter"
    html_content = f"""
    <!DOCTYPE html>
    <html lang=\"en\">
    <head>
        <meta charset=\"UTF-8\">
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
        <title>Welcome to Gibsey Bookclub β</title>
        <script src=\"{TAILWIND_CDN_URL}\"></script>
        <script>
          tailwind.config = {{ darkMode: 'class' }}; // Simplified config for CDN
        </script>
        <style>
          body {{ margin: 0; font-family: sans-serif; }}
          .prose h1 {{ margin-bottom: 0.5em; font-size: 2.25em; }}
          .prose h3 {{ margin-top: 1em; margin-bottom: 0.25em; font-size: 1.5em; }}
          .prose ul {{ list-style-type: decimal; margin-left: 1.5em; }}
          .prose blockquote {{ font-style: italic; border-left-color: #10B981; /* emerald-500 */ }}
        </style>
    </head>
    <body class=\"bg-gray-50 dark:bg-gray-900 text-gray-800 dark:text-gray-100 flex items-center justify-center min-h-screen p-4\">
        <div class=\"prose dark:prose-invert bg-white dark:bg-gray-800 p-8 rounded-lg shadow-xl max-w-2xl\">
            {html_body}
            <form method=\"post\" action=\"./enter\" class=\"mt-8\"> 
                <button type=\"submit\" class=\"w-full px-6 py-3 bg-emerald-600 text-white font-semibold rounded-lg shadow-md hover:bg-emerald-700 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-opacity-50 transition-colors\">
                    Enter Gibsey →
                </button>
            </form>
        </div>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)

@router.post("/enter", status_code=status.HTTP_303_SEE_OTHER)
async def handle_welcome_enter():
    """Sets a cookie to indicate the welcome screen has been seen and redirects to the reader."""
    response = RedirectResponse(url="/", status_code=status.HTTP_303_SEE_OTHER) # Redirect to root, App.jsx will handle view
    response.set_cookie(
        key="seen_welcome", value="1", max_age=31536000, 
        httponly=True, samesite="lax"
    )
    return response 