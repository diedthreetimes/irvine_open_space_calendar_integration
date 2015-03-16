The entire point of this project is to simply mirror http://letsgooutside.org/activities/ onto Google Calendar.
If you just want to add the calendar the mirror is live at https://www.google.com/calendar/embed?src=bWNxbnVlN3A3MDl2c21vYm9sOWw2dnB2aHNAZ3JvdXAuY2FsZW5kYXIuZ29vZ2xlLmNvbQ

If you want to run your own version (perhaps for your own local website) then read on.

This project requires you have a google API key.

If you have one already you should put in the secrets directory like so
$ ln -s ~/Dropbox/AppSecrets/openspace secrets


Run the following to create your own calendar and import all posted events
$ ./import_open_space_events.rb 
