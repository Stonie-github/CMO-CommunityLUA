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

-- Give a true/false respsponse as to if the Unit: threat, can reach distance: NM, from Unit:hav_asset, within the
-- time cap_time_to_area (Hours) + margin (Hours)
-- Example:  bool = estimate_intercept_threat_vs_asset(Unit, Unit, 0.5, 0.1, 50)
function estimate_intercept_threat_vs_asset (threat, hav_asset, cap_time_to_area, margin, distance )

        -- Prune contacts that are too far away to reach target within cap arrival time
        local threat_time_to_hva = time_to_target_with_margin(threat, hav_asset, distance)
        if ((cap_time_to_area - margin) > threat_time_to_hva) then
            --print("CAP will beat threat to area by " .. ((cap_time_to_area + margin)-threat_time_to_hva) .. " Hours")
            return false
        end

        -- How far can the threat go in the time it takes for CAP to arrive
        local threat_coverage = (cap_time_to_area+margin)*threat.speed
        local max_distance = math.ceil(threat_coverage)
        local interval = math.ceil(max_distance/10)
        for dist = 10,max_distance,interval do
            -- Create test point dist from threat bearing
            local intercept = World_GetPointFromBearing({latitude=threat.latitude, longitude=threat.longitude, distance=dist, bearing=threat.heading})
            -- Find distance from point to high value asset
            local point_distance = Tool_Range({ latitude=hav_asset.latitude, longitude=hav_asset.longitude},{ latitude=intercept.latitude, longitude=intercept.longitude })
            -- Debug to show points
            --local intercept_point = ScenEdit_AddReferencePoint( {side=script_side.name, longitude=intercept.longitude, latitude=intercept.latitude, highlighted=true })
            
            --print(point_distance)
            -- Check if distance is less than criteria
            if (point_distance < distance) then
                return true
            end
        end
        return false
end

-- Launch a HAVCAP mission with Unit: combat_ac, towards Unit:hva_ac, mission belongs to Side:script_side and mission name is a string
function lunch_havcap_mission(combat_ac, hva_ac, script_side, mission_name,parameters)
    local HAVUnit = ScenEdit_GetUnit(hva_ac)

    -- Add a tracking reference point 1 mile in front of unit
    local havLocation = ScenEdit_AddReferencePoint( {side=script_side.name, RelativeTo=HAVUnit.name, bearingtype='rotating', bearing=HAVUnit.heading ,distance=5,clear=true })
    
    -- Add a mission for the HAVCAP asset based on the reference point, Assign CAP
    local mission_config = { oneThirdRule=false, checkOPA=false, transitThrottleAircraft='Military', useFlightSize=false, attackDistanceAircraft=tostring(parameters.threat_zone) }
    local script_mission = ScenEdit_AddMission(script_side.name,mission_name, 'patrol',{type='AAW', zone={havLocation.name}})
    local script_mission = ScenEdit_SetMission(script_side.name,mission_name,mission_config)
    
    local dispatched = 0
    local num_ac = #combat_ac
    local loop_counter = 1
    repeat -- Cycle through cap list but quit when dispatch or end of available assets is reached
        local CAPUnit = ScenEdit_GetUnit(combat_ac[loop_counter])
        if(CAPUnit.readytime == '0') then -- Check if ready
            --Dispatch AC to mission
            ScenEdit_AssignUnitToMission(CAPUnit.name, mission_name)
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
                --print("Checking " .. threat.name)
                local is_threatened = estimate_intercept_threat_vs_asset(threat, hav_unit, launch_parameters.cap_time_to_hav, launch_parameters.cap_time_margin, launch_parameters.threat_zone)
                -- Only one threat is needed to give threatened status
                if (is_threatened == true) then
                    threatened = true
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

-- Check for mission go and dispatch mission if so
function sai_havcap_check_mission_go(mission, parameters)
    for k,v in ipairs(_G[mission]) do
        if(v >= parameters.threat_persistence_trigger_count) then
            --print("Threat established!")
            return true
        end
    end
end

-- Dispatch a mission to defend a asset
function sai_dispatch_mission(CAPLIST, HVALIST, script_side, actual_mission_name, mission_var, parameters)
    if ((mission_var.mission_launched == false) or (mission_var.mission_launched == nil)) then
        print("Launcing mission")
        lunch_havcap_mission(CAPLIST, HVALIST[1], script_side, actual_mission_name, parameters) -- FIX selection of HVA to laucn
        mission_var.mission_launched = true
    else
        print("No mission launched")
    end
end

-- Create mission variables if they dont exist NOT USED ATM
function sai_havcap_restore_mission_vars(mission_var, parameters)
    local str = mission_var
    -- Create global variable with threat counters
    if (_G[str] == nil) then
        --print("Creating threat counters")
        _G[str] = {}
        for k,v in ipairs(hva_asset_list) do
            _G[str][k] = 0
        end
        table.insert(_G[str].parameters, parameters)
    end
   
end

-------------------- START OF SCRIPT --------------------------------------------------------
SCRIPT_SIDE = "Opfor"
--------------------------------------------- ASSETS --------------------------------------
local HVALIST = { {name='SIGINT #1', side=SIDENAME}, {name="SIGINT #2", side="Opfor"}, { name="SIGINT #3", side="opfor" }, {name="SIGINT #4", side = "Opfor" }}
local CAPLIST = { {name="Rusky #1", side="Opfor"}, {name = "Rusky #2", side="Opfor"}, {name = "Rusky #3", side="Opfor"}, {name = "Rusky #4", side="Opfor"}, {name = "Rusky #5", side="Opfor"}, {name = "Rusky #6", side="Opfor"}}
local SCRIPT_MISSION = "HVAmission1" -- Must be unique!
local ACTUAL_MISSION_NAME = "HAVCAP MISSION"
--HVAmission1 = nil  -- Uncomment and run to reset mission status
--------------------------------------------- CONFIG ---------------------------------------
local parameters = { cap_time_to_hav=0.11, cap_time_margin=0.023, threat_zone=50, threat_persistence_trigger_count=4, dispatch_size=2}

--------------------------------------------- MAIN ---------------------------------
local script_side = VP_GetSide({name=SCRIPT_SIDE})

-- Populate potential air threats
local threatlist = {}
local threat_count = sai_populate_air_threat_list(threatlist, script_side.contacts)
--print("Found " .. threat_count .. " threats")

-- Make a index of threatened assets in the hav list
local threatened_assets = sai_havcap_evaluate_immediate_threats(HVALIST, threatlist, parameters)

-- Update threat counters
sai_update_threat_counters(HVALIST, threatened_assets, SCRIPT_MISSION)

-- Check for mission go
local mission_go = sai_havcap_check_mission_go(SCRIPT_MISSION, parameters)

--print(HVAmission1)
if (mission_go == true) then
    sai_dispatch_mission(CAPLIST, HVALIST, script_side, ACTUAL_MISSION_NAME,HVAmission1,parameters)
end