/*
    Hydration Reminder
    by Soulcloset
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
int RetryInterval = 10;

[Setting category="General" name="Reminder Interval (Minutes)" description="After this many minutes, you will be sent a reminder the next time you respawn." min=1]
int TimeInterval = 10;

[Setting category="General" name="Reminder Text" description="The message displayed when you are reminded to drink water."]
string ReminderText = "Drink some water!";

/*
//commented out because I don't know how to do centering when the window is not auto-resized
[Setting category="UI" name="Window Width" description="The width of the reminder window when it is shown. (Default: x)"]
int WindowWidth = 150;

[Setting category="UI" name="Window Height" description="The height of the reminder window when it is shown. (Default: y)"]
int WindowHeight = 100;
*/

[Setting category="UI" name="Popup Postion X" description="(Default: 960 - center)"]
int WindowPosX = 960;

[Setting category="UI" name="Popup Postion Y" description="(Default: 540 - center)"]
int WindowPosY = 540;

[Setting category="Developers" name="Verbose Mode" description="Enable/disable verbose logging to the Openplanet console. (Warning: this will spam the console)"]
bool verboseMode = false;

//[Setting category="Developers" name="Intruding Mode" description="test"]
bool intruding = false; //should the intrusive mode window be showing?


int curRetries = 0; //current retries
bool spawnLatch = false; //latch to check if player is in spawning state
string curMap = ""; //current map uid
bool logLatch = false; //latch to avoid repeat log messages from respawning
uint64 lastRemindTime = 0; //time in ms when the last reminder was sent
bool timeLatch = false; //latch to check if the time has been reached

//ui variables
vec2 scale = vec2(100, 40);
vec4 warningColor = vec4(0.9, 0.1, 0.1, 0.8); //red
vec4 successColor = vec4(0.1, 0.9, 0.1, 0.8); //green
float enabledHue = 0.25;
float enabledSat = 0.6805;
float enabledVal = 0.6627;

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
                lastRemindTime = Time::get_Now(); //reset timer for time logic
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
    auto app = cast<CTrackMania>(GetApp());
    auto RaceData = MLFeed::GetRaceData_V4();
    try{
        auto player = cast<MLFeed::PlayerCpInfo_V4>(RaceData.SortedPlayers_Race[0]);
        MLFeed::SpawnStatus currentSpawnStatus = player.SpawnStatus;
        
        if((Time::get_Now() - lastRemindTime) >= (TimeInterval * 60 * 1000)){
            //if the time since the last map change is greater than the interval, send reminder
            if(verboseMode){print("Time mode: time interval reached");}
            timeLatch = true; //set latch to notify on next respawn
            lastRemindTime = Time::get_Now(); //reset timer
            return true; //return true to indicate that the reminder was sent
        }

        if(timeLatch && currentSpawnStatus == MLFeed::SpawnStatus::Spawning){
            SendReminder();
            timeLatch = false; //reset latch
            lastRemindTime = Time::get_Now(); //redundant timer reset so the next reminder appears x minutes after you're notified
        }
    }
    catch{
        return false;
    }
    return false; //default return
}

void SendReminder(){
    //this will display the window for the reminder, interrupting gameplay
    if(verboseMode){print("Attempting reminder");}
    if(IntrusiveMode && !InServer()){
        intruding = true;
    }
    else {
        UI::ShowNotification("Hydration Reminder", ReminderText, successColor,  5000);
    }
}

void Render(){
    float pivotx = 0.5;
    float pivoty = 0.5;
    UI::SetNextWindowPos(WindowPosX, WindowPosY, UI::Cond::Appearing, pivotx, pivoty);
    //UI::SetNextWindowSize(WindowWidth, WindowHeight, UI::Cond::Appearing);
    if (intruding){
        UI::Begin("Hydrate", UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoScrollbar | UI::WindowFlags::NoCollapse | UI::WindowFlags::NoMove | UI::WindowFlags::NoResize);
        UI::SetNextItemWidth(0.9);
        UI::Text(ReminderText);
        if(UI::ButtonColored("Done!", enabledHue , enabledSat, enabledVal, scale)){
            intruding = false;
            UI::ShowNotification("Hydration Reminder", "Reminder dismissed.", successColor,  5000);
        }
        UI::End();
    }
}