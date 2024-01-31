#
# Matter_Plugin_2_Thermostat.be - implements the behavior for HVAC Thermostat
#
# Copyright (C) 2023  Stephan Hadinger & Theo Arends
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

import matter

# Matter plug-in for core behavior

#@ solidify:Matter_Plugin_Thermostat_Tuya,weak

class Matter_Plugin_Thermostat_Tuya : Matter_Plugin_Thermostat  
  static var TYPE = "thermostat_tuya"               # name of the plug-in in json
  static var DISPLAY_NAME = "Thermostat (Tuya)"     # display name of the plug-in
  
  static var ARG  = "dpid"                          # additional argument name (or empty if none)
  #static var ARG_TYPE = / x y -> int(x) int(y)     # function to convert argument to the right type
  static var ARG_HINT = "TarTemp,CurTemp,WorkMode,Switch"

  var dpid_filter
  var rule_installed
  var valueChanged

  #############################################################
  # Constructor
  def init(device, endpoint, arguments)
    super(self).init(device, endpoint, arguments)
    print (self.DISPLAY_NAME, "init(", str(device), ",", str(endpoint),",",str(arguments),")")
    
    # Overwrite the Matter defaults for the thermostat cluster by Tuya defaults
    self.shadow_abs_min_heat_setpoint_limit = 500   # default = 5°C
    self.shadow_abs_max_heat_setpoint_limit = 3000  # default = 30°C
    self.shadow_abs_min_cool_setpoint_limit = 500   # default = 5°C
    self.shadow_abs_max_cool_setpoint_limit = 3000  # default = 30°C
    self.shadow_min_heat_setpoint_limit = self.shadow_abs_min_heat_setpoint_limit
    self.shadow_max_heat_setpoint_limit = self.shadow_abs_max_heat_setpoint_limit
    self.shadow_min_cool_setpoint_limit = self.shadow_abs_min_cool_setpoint_limit
    self.shadow_max_cool_setpoint_limit = self.shadow_abs_max_cool_setpoint_limit
    self.shadow_control_sequence = 2                # default = 2 = HeatingOnly
    self.shadow_system_mode = 4                     # default = 4 = Heating

    self.dpid_filter = []
    self.valueChanged = nil
    self.parse_configuration(arguments)
  end

  #############################################################
  # Destructor
  def deinit(device, endpoint)
    print (self.DISPLAY_NAME, "deinit(", str(device), ", ", str(endpoint),")")
    self.delete_rule()
  end

  def add_rule()
    if self.rule_installed == nil || self.rule_installed == false
      print(self.DISPLAY_NAME, " add rule to receive TuyaReceived msgs")
      tasmota.add_rule("TuyaReceived", /data -> self.tuya_decode_and_get_dp(data), "ThermTuya")
      self.rule_installed = true
    end
  end

  def delete_rule()
    # remove previous rule if any
    if self.rule_installed != nil
      print(self.DISPLAY_NAME, "delete rule to receive TuyaReceived msgs")
      tasmota.remove_rule("TuyaReceived", "ThermTuya")
      self.rule_installed = false
    end
  end

  def set_dpid (arguments)
    import string
    if arguments != nil
      var dpids = arguments.find(self.ARG)   
      self.dpid_filter = string.split(dpids, ",")
      print(self.DISPLAY_NAME, "self.dpid_filter:", self.dpid_filter)
      #todo add some further checks for the user input!
    else
      print(self.DISPLAY_NAME, "arguments nil")
    end
  end

  def is_Id_in_filter (key)
    import string
    if nil == key || nil == self.dpid_filter
      return nil
    end
    
    var keySplit = string.split(key, "DpType")
    #print(size(keySplit), keySplit)
    keySplit = string.split(keySplit[1], "Id")
    #print(size(keySplit), keySplit)
    var dpType = number(keySplit[0])
    #print ("DpType extracted: ", dpType)
    var dpId = number(keySplit[1])
    #print(self.DISPLAY_NAME, "dpId: ", str(dpId))
    for idx: 0 .. (size(self.dpid_filter) - 1)
      #print(self.DISPLAY_NAME, "is_Id_in_filter idx", str(idx), str(self.dpid_filter[idx]))
      if dpId == number(self.dpid_filter[idx])
        #print(self.DISPLAY_NAME, "is_Id_in_filter Found:", dpId)
        return dpId
      end
    end
    return nil
  end

  def tuya_decode_and_get_dp(data)
    import string
    #print(self.DISPLAY_NAME, "tuya_decode_and_get_dp(), ", str(data))
    if data['Cmnd'] == 7 && data['CmndData'] != nil
      for key:data.keys()
        if 0 == string.find(key, "DpType")
          #print(self.DISPLAY_NAME, "tuya_decode_and_get_dp(), key = ", key)
          var dpId = self.is_Id_in_filter(key)
          if dpId != nil
            var rawValue = data[key]
            var formatedForMatterValue = rawValue
            if dpId == number(self.dpid_filter[0])   #target temperature
              print(self.DISPLAY_NAME, "Received target temperature on dpID[" ,dpId, "] =", rawValue)
              
              #TODO: ich muss erst sicher sein, in welchem Mode der Regler läuft, bevor ich hier etwas entscheiden kann!
              # eigentlich wäre ein Antriggern aller Datenpunkte zu Begin / Initialisierung sinnvoll! Es ist ja nicht immer gesagt, 
              # dass die TuyaMCU mit neustartet. Ggf werden auch keine Datenpunkte empfangen, wenn der Regler im Off Mode ist. 
              # ein Abfragen aller Datenpunkte ist also sinnvoll!
              formatedForMatterValue *= 10
              if (self.shadow_system_mode == 3)
                print(self.DISPLAY_NAME, "-> converted to OccupiedCoolingSetPoint =", formatedForMatterValue)
                self.shadow_target_temp_cool = formatedForMatterValue
              else
                print(self.DISPLAY_NAME, "-> converted to OccupiedHeatingSetPoint =", formatedForMatterValue)
                self.shadow_target_temp_heat = formatedForMatterValue
              end
            elif dpId == number(self.dpid_filter[1])     #current temperature
              print(self.DISPLAY_NAME, "Received current temperature on dpID[" ,dpId, "] =", rawValue)
              formatedForMatterValue *= 10
              self.shadow_current_temperature = formatedForMatterValue
              print(self.DISPLAY_NAME, "-> converted to LocalTemperature =", formatedForMatterValue)
            elif dpId == number(self.dpid_filter[2])     #working mode
              print(self.DISPLAY_NAME, "Received working mode on dpID[" ,dpId, "] =", rawValue)
              
              formatedForMatterValue = rawValue + 3      # conversion to SystemMode
              print(self.DISPLAY_NAME, " -> converted to SystemMode =", formatedForMatterValue)
              self.shadow_system_mode = formatedForMatterValue

              formatedForMatterValue = rawValue * 2     # conversion to ControlSequenceOfOperation
              print(self.DISPLAY_NAME, " -> converted to ControlSequenceOfOperation =", formatedForMatterValue)
              self.shadow_control_sequence = formatedForMatterValue
            elif dpId == number(self.dpid_filter[3])     # switch
              print(self.DISPLAY_NAME, "Received switch on dpID[" ,dpId, "] =", rawValue)
              
              if (0 == rawValue)
                formatedForMatterValue = 0
              elif (2 == self.shadow_control_sequence) 
                formatedForMatterValue = 4
              elif (0 == self.shadow_control_sequence)
                formatedForMatterValue = 3
              end

              print(self.DISPLAY_NAME, " -> converted to SystemMode =", formatedForMatterValue)
              self.shadow_system_mode = formatedForMatterValue
#-
            elif dpId == number(self.dpid_filter[4])     # set temperature upper limit
              # TODO --> set shadow_max_heat_setpoint_limit and shadow_max_cool_setpoint_limit (MaxHeat­Set­pointLimit / MaxCool­Set­pointLimit)
            elif dpId == number(self.dpid_filter[5])     # set temperature lower limit
              # TODO --> set shadow_min_heat_setpoint_limit and shadow_min_cool_setpoint_limit (MinHeat­Set­pointLimit / MinCool­Set­pointLimit)
            elif dpId == number(self.dpid_filter[6])     # child lock
              # TODO --> set shadow_child_lock (Keypad­Lockout)
            elif dpId == number(self.dpid_filter[7])     # Run mode
              # TODO --> set shadow_schedule_programming_visible (Sched­ulePro­gram­mingVisi­bility)
-#
            end
            self.valueChanged = dpId
            self.update_shadow()
            return
          end
        end
      end
    end
    return
  end

  #############################################################
  # parse_configuration
  #
  # Parse configuration map
  def parse_configuration(config)
    import string
    print(self.DISPLAY_NAME, "parse_configuration(",str(config),")")

    self.set_dpid(config)
    if self.dpid_filter && size(self.dpid_filter)
      self.add_rule()
      # trigger all data points from tuya
      # tasmota.cmd("TuyaSend8")
    else
      self.delete_rule()
    end

  end

  #############################################################
  # Update shadow
  # TODO: Ich weis noch nicht ob ich das hier wirklich brauche! Scheint mir bisher nur ein Umweg in die value_changed() 
  # Funktion zu sein!
  def update_shadow()
    import string
    if !self.VIRTUAL
      if self.valueChanged != nil
        #print(self.DISPLAY_NAME, "update_shadow(dpID =", str(self.valueChanged), ")")
        self.value_changed()
        self.valueChanged = nil
      end
    end
    super(self).update_shadow()
  end

  #############################################################
  # Called when the value changed compared to shadow value
  #
  # This must be overriden.
  # This is where you call `self.attribute_updated(<cluster>, <attribute>)`
  def value_changed()
    #print(self.DISPLAY_NAME, "value_changed()")
    if self.valueChanged == number(self.dpid_filter[0])
      #print(self.DISPLAY_NAME, " -> target temperature changed")
      self.attribute_updated(0x0201, 0x0011)
      self.attribute_updated(0x0201, 0x0012)
    elif self.valueChanged == number(self.dpid_filter[1])
      #print(self.DISPLAY_NAME, " -> current temperature changed")
      self.attribute_updated(0x0201, 0x0000)
    elif self.valueChanged == number(self.dpid_filter[2])
      #print(self.DISPLAY_NAME, " -> mode changed")
      self.attribute_updated(0x0201, 0x001B)
      self.attribute_updated(0x0201, 0x001C)
    elif self.valueChanged == number(self.dpid_filter[3])
      #print(self.DISPLAY_NAME, " -> switch changed")
      self.attribute_updated(0x0201, 0x001C)
    end
  end
  
  #############################################################
  # Write attribute
  #
  def write_attribute(session, ctx, write_data)
    import string
    var TLV = matter.TLV
    var cluster = ctx.cluster
    var attribute = ctx.attribute
    var formatedForTuya = write_data

    print(self.DISPLAY_NAME, "write_attribute(",string.hex(ctx.cluster), string.hex(ctx.attribute), str(write_data),")")

    if cluster == 0x0201              # ========== Thermostat ==========
      if attribute == 0x0011          # ---------- Occu­piedCoolingSet­point ----------
        if type(write_data) == 'int'
          print(self.DISPLAY_NAME, "Received OccupiedCoolingSetpoint =", write_data)
          self.shadow_target_temp_cool = write_data

          formatedForTuya /= 10
          print(self.DISPLAY_NAME, " -> converted to target temperature =", formatedForTuya)
          var command = "TuyaSend2 " + self.dpid_filter[0] + "," + str(formatedForTuya)
          tasmota.cmd(command)

          self.valueChanged = number(self.dpid_filter[0])
          self.update_shadow()
          return true
        end
      elif attribute == 0x0012          # ---------- Occu­piedHeat­ingSet­point ----------
        if type(write_data) == 'int'
          print(self.DISPLAY_NAME, "Received OccupiedHeatingSetpoint =", write_data)
          self.shadow_target_temp_heat = write_data

          formatedForTuya /= 10
          print(self.DISPLAY_NAME, " -> converted to target temperature =", formatedForTuya)
          var command = "TuyaSend2 " + self.dpid_filter[0] + "," + str(formatedForTuya)
          tasmota.cmd(command)
          
          self.valueChanged = number(self.dpid_filter[0])
          self.update_shadow()
          return true
        end
      elif attribute == 0x001C          # ---------- SystemMode ----------
        if type(write_data) == 'int'
          print(self.DISPLAY_NAME, "Received SystemMode =", write_data)
          self.shadow_system_mode = write_data

          if self.shadow_system_mode == 0       # Off
            print(self.DISPLAY_NAME, " -> converted to switch =", formatedForTuya)
            var command = "TuyaSend1 " + self.dpid_filter[3] + "," + str(formatedForTuya)
            tasmota.cmd(command)
          elif self.shadow_system_mode ==  3 || self.shadow_system_mode ==  4    # Cool or heat
            formatedForTuya -= 3
            print(self.DISPLAY_NAME, " -> converted to mode =", formatedForTuya)
            var command = "Backlog TuyaSend1 " + self.dpid_filter[3] + ", 1;" + "TuyaSend4 " + self.dpid_filter[2] + "," + str(formatedForTuya)
            tasmota.cmd(command)
          end
          self.valueChanged = number(self.dpid_filter[3])
          self.update_shadow()
          return true
        end
      else
        print (self.DISPLAY_NAME, "unknown write_attribute!")
      end
    end
  end

  #############################################################
  # Invoke a command
  #
  # returns a TLV object if successful, contains the response
  #   or an `int` to indicate a status
  def invoke_request(session, val, ctx)
    import string
    print(self.DISPLAY_NAME, "invoke_request(",string.hex(ctx.cluster), string.hex(ctx.command),")")
    var TLV = matter.TLV
    var cluster = ctx.cluster
    var command = ctx.command

    # ====================================================================================================
    if cluster == 0x0201              # ========== Thermostat ==========
      self.update_shadow_lazy()
      if command == 0x0000                #  ---------- Set­pointRaiseLower ----------
        print(self.DISPLAY_NAME, "invoke_request -> SetpointRaiseLower")
        return true
      end
    end
    # else
    return super(self).invoke_request(session, val, ctx)

  end

end

matter.Plugin_Thermostat_Tuya = Matter_Plugin_Thermostat_Tuya
