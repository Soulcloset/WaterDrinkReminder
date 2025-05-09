/*
    Hydration Reminder
    by Soulcloset
*/

/*
    TODO:
    - Displaying reminder as a pop-up window with a clickable button to close
    - Showing reminder when dictated by settings
        - Every X retries
        - Every X minutes?? maybe??
    - Less intrusive showNotification at launch when reminders are disabled
        - This is to remind the user to enable if wanted
    - Check that user is in solo to avoid cotd interruptions
*/

enum intervaltypes {
    Retries,
    Minutes,
    Both
}

[Setting category="General" name="Enable reminders" description="When checked, you will be reminded to drink water per the settings below. (Warning: this may interrupt gameplay)"]
bool RemindersEnabled = false;

[Setting category="General" name="Intrusive Reminders" description="When checked, reminders in Solo mode will be shown as a pop-up window which must be dismissed. When unchecked or when on a server, reminders will be shown as a notification."]
bool IntrusiveMode = true;

[Setting category="General" name="Interval Type" description="Choose the type of interval for reminders."]
intervaltypes IntervalType = intervaltypes::Retries;

[Setting category="General" name="Reminder Interval (Retries)" description="After this many retries on the same map, you will be sent a reminder." min=1]
int RetryInterval = 5;

[Setting category="General" name="Reminder Interval (Minutes)" description="After this many minutes, you will be sent a reminder the next time you respawn." min=1]
int TimeInterval = 5;

[Setting category="General" name="Reminder Text" description="The message displayed when you are reminded to drink water."]
string ReminderText = "Drink some water!";

[Setting category="Developers" name="Verbose Mode" description="Enable/disable verbose logging to the Openplanet console. (Warning: this will spam the console)"]
bool verboseMode = false;


int curRetries = 0; //current retries
bool spawnLatch = false; //latch to check if player is in spawning state
string curMap = ""; //current map uid
bool logLatch = false; //latch to avoid repeat log messages from respawning

//ui variables
vec4 warningColor = vec4(0.9, 0.1, 0.1, 0.8); //red
vec4 successColor = vec4(0.1, 0.9, 0.1, 0.8); //green

void Main(){
    print("Loaded WaterDrinkReminder!");

    if(RemindersEnabled){
        if(verboseMode){print("Reminders are enabled at startup");}
    }
    else {
        if(verboseMode){print("Reminders are disabled at startup");}
        UI::ShowNotification("Hydration Reminder", "Reminders are disabled! Visit the Openplanet Settings to enable.", warningColor,  5000);
    }

    while(true){
        if(RemindersEnabled){
            switch(GetIntervalType()){
                case 0:
                    //retries
                    RetryLogic();
                    break;
                case 1:
                    //minutes
                    TimeLogic();
                    break;
                case 2:
                    //both
                    if(!TimeLogic()){
                        //if the reminder is triggered by time, skip checking for retries
                        RetryLogic();
                    }
                    else {
                        if(verboseMode){print("Both setting - skipped retry check due to time");}
                    }
                    break;
                default:
                    //invalid
                    if(verboseMode){print("Invalid interval type!");}
            }
        }
        yield();
    }

}

bool InServer(){
        CTrackManiaNetwork@ Network = cast<CTrackManiaNetwork>(GetApp().Network);
        CGameCtnNetServerInfo@ ServerInfo = cast<CGameCtnNetServerInfo>(Network.ServerInfo);
        return ServerInfo.JoinLink != "";
    }

int GetIntervalType(){
    //this will return the interval type based on the setting
    //0 = retries, 1 = minutes
    if(IntervalType == intervaltypes::Retries){
        return 0;
    }
    else if(IntervalType == intervaltypes::Minutes){
        return 1;
    }
    else {
        return 2;
    }
}

void RetryLogic(){
    //triggers reminders based on retries

    auto app = cast<CTrackMania>(GetApp());
    auto map = app.RootMap;
    auto RaceData = MLFeed::GetRaceData_V4();
    try{
    auto player = cast<MLFeed::PlayerCpInfo_V4>(RaceData.SortedPlayers_Race[0]);
        MLFeed::SpawnStatus currentSpawnStatus = player.SpawnStatus;

        // If the player is in spawning state, check if there was a map change. If so, set the latch to true.
        if (currentSpawnStatus == MLFeed::SpawnStatus::Spawning && map.MapInfo.MapUid != curMap) {
            spawnLatch = true;
            curMap = map.MapInfo.MapUid;
            if(verboseMode){print("Map changed, latch set.");}
        }
        // If there was NOT a map change, the player IS in spawning state, AND the latch is true, return nothing.
        else if (currentSpawnStatus == MLFeed::SpawnStatus::Spawning && spawnLatch) {
            if(!logLatch){
                logLatch = true; //set latch to avoid repeat log messages
                if(verboseMode){print("Player is spawning, latch is true. Returning.");}
            }
            return;
        }
        // If the latch is true, check if the player is NOT in the spawning state. If so, set the latch to false.
        else if (spawnLatch && currentSpawnStatus != MLFeed::SpawnStatus::Spawning) {
            spawnLatch = false;
            logLatch = false;
            if(verboseMode){print("Player is no longer spawning, latch reset.");}
        }
        // If the latch is false AND the player is in spawning state, increment the retry count and set the latch.
        else if (!spawnLatch && currentSpawnStatus == MLFeed::SpawnStatus::Spawning) {
            if(verboseMode){print("Player is spawning, latch is false. Incrementing retry count.");}
            
            curRetries++; //increment retries
            if(verboseMode){print("Incremented retry count: " + curRetries);}

            //the below is the incrementing logic for retries, but needs to be triggered only by a respawn
            if(curRetries >= RetryInterval){
                if(verboseMode){print("Retry count reached or exceeded: " + curRetries);}
                SendReminder();
                curRetries = 0; //reset retries
            }

            spawnLatch = true; //set latch to avoid double counting
        }
    }
    catch{
        return;
    }

    
}

bool TimeLogic(){
    //triggers reminders based on minutes after next respawn
    //returns true if the reminder was sent - this is to facilitate the Both setting
    return false; //default return
}

void SendReminder(){
    //this will display the window for the reminder, interrupting gameplay
    if(verboseMode){print("Attempting reminder");}
    if(IntrusiveMode && !InServer()){
        //popup window
        if(UI::Begin("Hydration Reminder", IntrusiveMode, UI::WindowFlags::NoCollapse | UI::WindowFlags::MenuBar)){
            UI::Text(ReminderText);
        }
    }
    else {
        UI::ShowNotification("Hydration Reminder", ReminderText, successColor,  5000);
    }
}