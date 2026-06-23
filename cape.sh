#!/bin/bash

#############
###BlooGuy###
#####V1######
##6/22/2026##
#############

#Config

KOMGA_URL="REPLACE_ME_URL"
USERNAME="REPLACE_ME_EMAIL"
PASSWORD="REPLACE_ME_PASSWORD"


#Default settings
DISPLAY_MODE="ascii"
SCREENSAVER=false
VERBOSE=false
CURRENT_ID=""
CURRENT_TMP_IMG=$(mktemp /tmp/cape_XXXXXX.jpg)
IS_DRAWING=false

#Cleanup
trap 'rm -f "$CURRENT_TMP_IMG"' EXIT

#Clean Exit
handle_interrupt() {
  clear
  exit 0
}
trap handle_interrupt SIGINT SIGTERM

#Redraw for term resize
redraw_screen() {
  if [ "$IS_DRAWING" = true ]; then
    return
  fi
  IS_DRAWING=true

  if [ -s "$CURRENT_TMP_IMG" ]; then
    clear 
    
    local term_cols=$(tput cols)
    local term_lines=$(tput lines)
    
    term_cols=${term_cols:-80}
    term_lines=${term_lines:-24}

    local offset=1
    if [ "$VERBOSE" = true ] && [ "$SCREENSAVER" = true ]; then
      offset=4
      
      local title
      if [ "$DISPLAY_MODE" = "thumbnail" ]; then
        title="[ High-Res Cover (ID: $CURRENT_ID) | Press Ctrl+C to exit ]"
      else
        title="[ ASCII Cover (ID: $CURRENT_ID) | Press Ctrl+C to exit ]"
      fi
      printf "%*s\n\n" $(( (${#title} + term_cols) / 2)) "$title"
    fi
    
    local img_lines=$((term_lines - offset))

    if [ "$DISPLAY_MODE" = "thumbnail" ]; then
      chafa --format=kitty --size="${term_cols}x${img_lines}" --align=center,center "$CURRENT_TMP_IMG"
    else
      chafa --format=symbols --symbols ascii --size="${term_cols}x${img_lines}" --align=center,center "$CURRENT_TMP_IMG"
    fi
  fi
  
  IS_DRAWING=false
}
trap redraw_screen SIGWINCH

#Arg Parser

show_help() {
  echo "Usage: cape [-t] [-s] [-v] [book_id | duration]"
  echo "Options:"
  echo "  -t    Display high-res thumbnail instead of ASCII (Kitty/iTerm2)"
  echo "  -s    Screensaver mode (cycles random covers)"
  echo "  -v    Verbose mode: shows ID and exit instructions (screensaver only)"
  echo ""
  echo "Screensaver Duration:"
  echo "  Provide a time: <number>s (seconds), <number>m (minutes), or just <number>."
  echo "  Default is 5m. Maximum is 60m (3600s)."
}

if [ "$#" -eq 0 ]; then
  show_help
  exit 0
fi

while getopts "htsv" opt; do
  case ${opt} in
    t ) DISPLAY_MODE="thumbnail" ;;
    s ) SCREENSAVER=true ;;
    v ) VERBOSE=true ;;
    h )
      show_help
      exit 0
      ;;
    \? )
      echo "Invalid option: -$OPTARG" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

#Positional Arg Parser

if [ "$SCREENSAVER" = true ]; then
  DURATION_INPUT="$1"
  SLEEP_SECONDS=300

  if [ -n "$DURATION_INPUT" ]; then
    if [[ "$DURATION_INPUT" =~ ^([0-9]+)(s|m)?$ ]]; then
      VAL="${BASH_REMATCH[1]}"
      UNIT="${BASH_REMATCH[2]}"

      if [ -z "$UNIT" ] || [ "$UNIT" = "m" ]; then
        SLEEP_SECONDS=$((VAL * 60))
      elif [ "$UNIT" = "s" ]; then
        SLEEP_SECONDS=$VAL
      fi

      if (( SLEEP_SECONDS <= 0 || SLEEP_SECONDS > 3600 )); then
        echo "Error: Duration must be between 1 second and 60 minutes (3600s)."
        exit 1
      fi
    else
      echo "Error: Invalid duration format. Use <number>s, <number>m, or <number>."
      exit 1
    fi
  fi
else
  BOOK_ID="$1"
  if [ -z "$BOOK_ID" ]; then
    echo "Error: You must provide a Book ID unless using screensaver mode (-s)."
    exit 1
  fi
fi

#Fetch cover to display

fetch_and_display() {
  CURRENT_ID="$1"

  curl -s -f -u "$USERNAME:$PASSWORD" "$KOMGA_URL/api/v1/books/$CURRENT_ID/thumbnail" -o "$CURRENT_TMP_IMG"

  if [ $? -eq 0 ] && [ -s "$CURRENT_TMP_IMG" ]; then
    redraw_screen 
  else
    if [ "$VERBOSE" = true ]; then
      echo "Error: Could not fetch cover for ID: $CURRENT_ID"
    fi
  fi
}

#Loop

if [ "$SCREENSAVER" = true ]; then
  if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is required for screensaver mode to parse the API."
    exit 1
  fi

  if [ "$VERBOSE" = true ]; then
    echo "Fetching library data from Komga..."
  fi
  
  ALL_BOOKS=$(curl -s -f -u "$USERNAME:$PASSWORD" "$KOMGA_URL/api/v1/books?size=100000" | jq -r '.content[].id')
  
  if [ -z "$ALL_BOOKS" ]; then
    echo "Error: Could not retrieve book list from Komga."
    exit 1
  fi

  mapfile -t BOOK_ARRAY <<< "$ALL_BOOKS"
  
  while true; do
    SHUFFLED_BOOKS=($(shuf -e "${BOOK_ARRAY[@]}"))

    for id in "${SHUFFLED_BOOKS[@]}"; do
      fetch_and_display "$id"
      
      for (( i=0; i<SLEEP_SECONDS; i++ )); do
        sleep 1
      done
    done
  done

else
  fetch_and_display "$BOOK_ID"
  
  while true; do
    sleep 1
  done
fi
