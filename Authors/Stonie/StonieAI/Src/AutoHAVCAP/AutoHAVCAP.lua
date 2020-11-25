--Stonie's Command Mission AI suite : HAVCAP Response AI V0.1
--This script will lunch a fighter squadron to protect high value assets when it estimates an incoming contact may threaten it.

-- Time for Unit: self to reach Unit: target at the speed self is on as if it were heading straight for it
function time_to_target(self, target)
    return Tool_Range(self.guid, target.guid) / self.speed
end

--Time for Unit: self to reach Unit: target at the speed self is on as if it were heading straight for it and a 
--distance reduction of margin : NM was applied
-- Example: time = time_to_target_with_margin(Unit, Unit, 10) 
function time_to_target_with_margin(self, target, margin)
    --local time_to_target = time_to_target(self, target)
    --local time_margin_budget = 
    local distance = Tool_Range(self.guid, target.guid)
    if ((distance-margin) > 0) then
        return (distance-margin) / self.speed
    else
        return 0
    end
end

-- Time for Unit:threat to circular area of radii area_size : NM around Unit:target
function time_threat_to_defense_area(self, target, area_size)
    local threat_distance = Tool_Range(hav_asset.guid, threat.guid)
    return (threat_distance-area_size)/threat.speed
end

-- Give a true/false respsponse as to if the Unit:threat, can reach distance: NM, from Unit:hav_asset, within the
-- time cap_time_to_area (Hours) + margin (Hours)
-- Example:  bool = estimate_intercept_threat_vs_asset(Unit, Unit, 0.5, 0.1, 50)
function estimate_intercept_threat_vs_asset (threat, hav_asset, cap_time_to_area, margin, distance )

        local threat_distance = Tool_Range(hav_asset.guid, threat.guid)
        --print(threat_distance)

        -- Calculate distance between defense area and threat
        local distance_to_defense_area = threat_distance - distance

        --print("Threat distance to defense area " .. distance_to_defense_area)

        -- Check if contact is already within threat area
        if (distance_to_defense_area < 0) then -- Is threat within area already, uh oh! Lets mark as threat even if we dont know a lot about it
            return true
        end

        -- Evaluate how much we know about the contact, i.e speed and heading. If we dont lets ignore it on the ground we dont know enough
        if ((threat.speed == nil) or (threat.heading == nil)) then
            --print("Ignoring boogie with low certaintity")
            return false
        end
        
        -- Calculate time to defense area for target and compare to time for CAP to arrive to target
        -- if cap can arrive faster than target to defense area then no problem
        threat_time_to_defense_area = distance_to_defense_area / threat.speed
        if (threat_time_to_defense_area > (cap_time_to_area + margin)*1.1) then
            --print("CAP will beat threat to area by " .. ((cap_time_to_area + margin)-threat_time_to_defense_area) .. " Hours")
            return false
        end

        -- How far can the threat go in the time it takes for CAP to arrive
        local threat_coverage = (cap_time_to_area+margin)*threat.speed
        local max_distance = math.ceil(threat_coverage)
        local interval = math.ceil(max_distance/10)
        for dist = 1,8,1 do -- 8 * dist will be the maximum travel distance over cap_time_to_area+margin
            -- Create test point dist from threat bearing
            local intercept = World_GetPointFromBearing({latitude=threat.latitude, longitude=threat.longitude, distance=dist*interval, bearing=threat.heading})
            -- Find distance from point to high value asset
            local point_distance = Tool_Range({ latitude=hav_asset.latitude, longitude=hav_asset.longitude},{ latitude=intercept.latitude, longitude=intercept.longitude })
            -- Debug to show points
            --local intercept_point = ScenEdit_AddReferencePoint( {side="Bluefor", longitude=intercept.longitude, latitude=intercept.latitude, highlighted=true })
            
            --print(point_distance)
            -- Check if distance is less than criteria
            if (point_distance < distance) then
                return true
            end
        end
        return false
end

-- Launch a HAVCAP mission with Unit: combat_ac, towards Unit:hva_ac, mission belongs to Side:script_side and mission name is a string
function lunch_havcap_mission(combat_ac, hva_ac, script_side, mission_name, mission_var,parameters)
    local HAVUnit = ScenEdit_GetUnit(hva_ac)

    -- Check for existing mission
    if (mission_var.mission ~= nil) then
        if(mission_var.mission.name == mission_name) then
            print("Mission exists")
            --print(mission_var.mission.unitlist) -- Later we can use this to repopulate missions if they have no units assigned
            return -- Already exists
        end
    end
    if (mission_var.mission == nil) then -- Check for 'forgotten mission'
        
        --print("Check for existing mission")
        Tool_EmulateNoConsole(true)
        local script_mission = ScenEdit_GetMission(script_side.name, mission_name)
        Tool_EmulateNoConsole(false)

        if (script_mission ~= nil) then -- Mission found, recover knowledge of it
            mission_var.mission = script_mission
            mission_var.mission_launched = true
            print("Found existing mission, recovering")
            return -- Already exists and information is recovered
        end
    end

    -- Add a tracking reference point 1 mile in front of unit
    local havLocation = ScenEdit_AddReferencePoint( {side=script_side.name, RelativeTo=HAVUnit.name, bearingtype='rotating', bearing=HAVUnit.heading ,distance=5,clear=true })
    
    -- Add a mission for the HAVCAP asset based on the reference point, Assign CAP
    local mission_config = { oneThirdRule=false, checkOPA=false, transitThrottleAircraft='Military', useFlightSize=false, attackDistanceAircraft=tostring(parameters.threat_zone) }
    local script_mission = ScenEdit_AddMission(script_side.name,mission_name, 'patrol',{type='AAW', zone={havLocation.name}})
    local script_mission = ScenEdit_SetMission(script_side.name,mission_name,mission_config)
    mission_var.mission = script_mission
    
    local dispatched = 0
    local num_ac = #combat_ac
    local loop_counter = 1
    repeat -- Cycle through cap list but quit when dispatch or end of available assets is reached
        local CAPUnit = ScenEdit_GetUnit(combat_ac[loop_counter])
        if(CAPUnit.readytime == '0') then -- Check if ready
            --Dispatch AC to mission
            ScenEdit_AssignUnitToMission(CAPUnit.name, mission_name)
            CAPUnit.group = mission_name .. " intercept"
            dispatched = dispatched + 1
            --print("Dispatching A/C to mission")
        end
        
        loop_counter = loop_counter + 1
    until ((loop_counter == num_ac) or (dispatched == parameters.dispatch_size))
end

-- Populate the table passed to this function with air contacts with contacts from side.contacts
function sai_populate_air_threat_list(table_to_populate, contact_list)
    local num_air_contacts = 0
    for k,v in ipairs(contact_list) do
        local contact = VP_GetContact({guid=v.guid})
        if contact.type == 'Air' then
            table.insert(table_to_populate, v)
            num_air_contacts = num_air_contacts + 1
        end
    end
    return num_air_contacts
end

-- Check to see if mission should be launched, given the current list of high value assets hva_asset_list, cap_asset_list, threatlist with contacts 
-- and parameters (launch_parameters) {Ex parameters cap_time_to_hav=0.11, cap_time_margin=0.023, threat_zone=50 }
-- Returns a table of booleans over threatened assets with index corresponding to the hva list
function sai_havcap_evaluate_immediate_threats(hva_asset_list, threatlist, launch_parameters)
    local ret = {}
    for k,v in ipairs(hva_asset_list) do

        local hav_unit = ScenEdit_GetUnit(v)

        if (hav_unit.condition == 'Airborne') then  -- Skip flights that are not airborne
            --print("Checking threat against asset " .. v.name)
            local threatened = false

            for k,v in ipairs(threatlist) do
                local threat = VP_GetContact({guid=v.guid})
                print("Checking " .. threat.name)
                local is_threatened = estimate_intercept_threat_vs_asset(threat, hav_unit, launch_parameters.cap_time_to_hav, launch_parameters.cap_time_margin, launch_parameters.threat_zone)
                -- Only one threat is needed to give threatened status
                if (is_threatened == true) then
                    threatened = true
                    print(hav_unit.name .. " is threatened")
                end
           end
            table.insert(ret, threatened) 
        else
            table.insert(ret, false) 
            --print("Skipping non-airborne asset")
        end
    end

    return ret
end

-- Creates if needed but otherwise updates mission threat counter for hva_asset_list, global 
-- containign results will be created named after hva_threat_counter_global_name_string
function sai_update_threat_counters(hva_asset_list, threatened_assets, hva_threat_counter_global_name_string)
    local str = hva_threat_counter_global_name_string
    -- Create global variable with threat counters
    if (_G[str] == nil) then
        --print("Creating threat counters")
        _G[str] = {}
        for k,v in ipairs(hva_asset_list) do
            _G[str][k] = 0
        end
    end
    --print(hva_threat_counters)

    --Increment threat counters
    for k,v in ipairs(threatened_assets) do
        if(v) then
            _G[str][k] = _G[str][k] + 1
        else
            _G[str][k] = 0
        end
    end
end

-- Check for mission go and dispatch mission if so. Will launch cap to the first persistently threated hva found, its not very intelligent yet
function sai_havcap_mission_dispatch(CAPLIST, HVALIST, script_side, actual_mission_name, mission_var, parameters)
    for k,v in ipairs(mission_var) do
        if(v >= parameters.threat_persistence_trigger_count) then
            -- Only lunch missions for airborne units
            HVAUnit = ScenEdit_GetUnit(HVALIST[k])
            if (HVAUnit.condition == 'Airborne') then  -- Skip flights that are not airborne
                lunch_havcap_mission(CAPLIST, HVALIST[k], script_side, actual_mission_name, mission_var, parameters)
            else
                v = 0   -- Set threat count to 0 if non airborne threatened hva ends up here for some reason
            end
            return true
        end
    end
end

-- Create mission variables if they dont exist NOT USED ATM
function sai_havcap_restore_mission_vars(mission_var, parameters)
    local str = mission_var
    -- Create global variable with threat counters
    if (_G[str] == nil) then
        print("Creating threat counters")
        _G[str] = {}
        for k,v in ipairs(hva_asset_list) do
            _G[str][k] = 0
        end
        table.insert(_G[str].parameters, parameters)
    end
end


-------------------- START OF SCRIPT --------------------------------------------------------
SCRIPT_SIDE = "Opfor" -- The side owning the assets the script manages
--------------------------------------------- ASSETS --------------------------------------
local HVALIST = { {name='SIGINT #1', side=SIDENAME}, {name="SIGINT #2", side="Opfor"}, { name="SIGINT #3", side="Opfor" }, {name="SIGINT #4", side = "Opfor" }}
local CAPLIST = { {name="Rusky #1", side="Opfor"}, {name = "Rusky #2", side="Opfor"}, {name = "Rusky #3", side="Opfor"}, {name = "Rusky #4", side="Opfor"}, {name = "Rusky #5", side="Opfor"}, {name = "Rusky #6", side="Opfor"}, {name = "Rusky #7", side="Opfor"}, {name = "Rusky #8", side="Opfor"}, {name = "Rusky #9", side="Opfor"}, {name = "Rusky #10", side="Opfor"}, {name = "Rusky #11", side="Opfor"}, {name = "Rusky #12", side="Opfor"}}
local SCRIPT_MISSION_VAR = "HVAmission1" -- Must be unique, script will create a global variable with the name of this string!
local ACTUAL_MISSION_NAME = "HAVCAP MISSION" -- Name of the mission in the editor
--------------------------------------------- CONFIG ---------------------------------------
-- Some config parameters passed into the function
-- cap_time_to_hav is the estimated time in hours for combat a/c to reach the high value asset. Ballpark is distance from hva to combat aircraft base divided with the typical speed of the fighters
-- cap_time_margin is extra "margin" added on top of this time. The decision to launch combat aircraft is made to try to get combat a/c to hva the margin before threat reaches the area within threat_zone miles of the high value asset
-- threat_zone is the area which is considered threatening for a contact to be within before the combat aircraft arrive
-- threat_persistence_trigger_count is how many times the script finds a threat threatening (heading towards the asset) before a mission is launched. If the script is triggered 4 times per minute and the trigger_count is 4 the asset must be
--      threatened for a total of a minute before mission is launched, take this into account in the margin needed
-- dispatch_size is how many available assets are recruited to the mission. Script will look for dispatch_size ready aircraft in the list.
local parameters = { cap_time_to_hav=0.11, cap_time_margin=0.023, threat_zone=60, threat_persistence_trigger_count=4, dispatch_size=4} 

--------------------------------------------- MAIN ---------------------------------
local script_side = VP_GetSide({name=SCRIPT_SIDE})

--HVAmission1 = nil  -- Uncomment and run to reset mission state

--print("HVAmission1.mission")

print("Running HAVCAP " .. SCRIPT_MISSION_VAR)

-- Populate potential air threats
local threatlist = {}
local threat_count = sai_populate_air_threat_list(threatlist, script_side.contacts)

-- Make a index of threatened assets in the hav list
local threatened_assets = sai_havcap_evaluate_immediate_threats(HVALIST, threatlist, parameters)

-- Update threat counters, this function actually creates the global state variable if it does not exist.
sai_update_threat_counters(HVALIST, threatened_assets, SCRIPT_MISSION_VAR)

-- Check for mission go, use the mission variable directly instead of string here now that it has been created
local mission_go = sai_havcap_mission_dispatch(CAPLIST, HVALIST, script_side, ACTUAL_MISSION_NAME,HVAmission1, parameters)

--print(HVAmission1) -- If you want to see threat counters uncommment this