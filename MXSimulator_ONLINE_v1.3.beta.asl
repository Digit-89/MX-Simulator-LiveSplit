state("mx") {
	int playerID         : "mx.exe", 0x20D1B0;
	int playersInRace    : "mx.exe", 0x4325538;

	int firstLapCPs      : "mx.exe", 0x4323704;
	int normalLapCPs     : "mx.exe", 0x4323708;

	//double tickRate      : "mx.exe", 0x162B90;
	int raceTicks        : "mx.exe", 0x4324898;
	//int serverStartTicks : "mx.exe", 0x43248A0;

	string512 trackName  : "mx.exe", 0x43212B8, 0x0;
}

startup {
	vars.timerModel = new TimerModel { CurrentState = timer };

	settings.Add("cpNumberHint", true, "Display a hint when number of checkpoints and splits doesn't line up");

	vars.timerStart = (EventHandler) ((s, e) => {
		vars.validLap = true;
	});
	timer.OnStart += vars.timerStart;

	timer.CurrentTimingMethod = TimingMethod.GameTime;
}

init {
	current.CPs = 0;
	current.id = 0;
	vars.startTicks = 0;

	vars.CPsChanged = false;
	vars.onFinalSplit = false;
	vars.onFirstCP = false;
	vars.validLap = true;

	vars.checkpointWatcher = (MemoryWatcher<int>)null;
	vars.idWatcher = (MemoryWatcher<int>)null;

	vars.updateWatchers = (Action) (() => {
		if (current.playersInRace > 0) {
			IntPtr ptr = IntPtr.Zero;
			for (int i = 0; i < current.playersInRace; ++i) {
				vars.idWatcher = new MemoryWatcher<int>(new DeepPointer("mx.exe", 0x4324DB8 + 0xC * i));
				vars.idWatcher.Update(game);

				if (vars.idWatcher.Current == current.playerID) {
					vars.checkpointWatcher = new MemoryWatcher<int>(new DeepPointer("mx.exe", 0x4324DBC + 0xC * i));
					break;
				}
			}
		}
	});

	vars.message = (Action) (() => {
		DialogResult result = DialogResult.None;
		if (settings["cpNumberHint"] && current.normalLapCPs > 0 && timer.Run.Count != current.normalLapCPs)
			result = MessageBox.Show(
				"You currently have " + timer.Run.Count + " splits, but this track " + current.trackName + " has " + current.normalLapCPs + " checkpoints!\n\n" +
				"Do you want to save your splits now and generate new ones for this track?",
				"MX Simulator Auto Splitter",
				MessageBoxButtons.YesNo,
				MessageBoxIcon.Information
			);

		if (result == DialogResult.Yes) {
			LiveSplitState _state = (LiveSplitState)new LiveSplitState(timer.Run, timer.Form, timer.Layout, timer.LayoutSettings, timer.Settings).Clone();
			_state.Form.ContextMenuStrip.Items["saveSplitsAsMenuItem"].PerformClick();

			int currAmtSplits = timer.Run.Count;

			for (int gateNo = 1; gateNo <= current.normalLapCPs; ++gateNo)
				timer.Run.Add(new Segment("Gate " + gateNo));

			for (int splitNo = 1; splitNo <= currAmtSplits; ++splitNo)
				timer.Run.RemoveAt(0);

			timer.Run.GameName = "MX Simulator";
			timer.Run.CategoryName = current.trackName;
		}
	});

	vars.wait = (Action<int>) ((time) => {
		System.Threading.Tasks.Task.Run(async () => {
			await System.Threading.Tasks.Task.Delay(time);
		}).Wait();
	});

	vars.updateWatchers();
	vars.message();
}

update {
	if (vars.idWatcher == null || vars.checkpointWatcher == null) {
		vars.updateWatchers();
		return false;
	}

	vars.idWatcher.Update(game);
	vars.checkpointWatcher.Update(game);
	current.CPs = vars.checkpointWatcher.Current;
	current.id = vars.idWatcher.Current;

	vars.CPsChanged = old.id == current.id && old.CPs != current.CPs || old.id != current.id && old.CPs == current.CPs;
	vars.onFinalSplit = timer.CurrentSplitIndex == timer.Run.Count - 1;
	vars.onFirstCP = (current.CPs - current.firstLapCPs) % current.normalLapCPs == 0;

	if (current.id != current.playerID) vars.updateWatchers();

	if (settings.ResetEnabled && timer.CurrentPhase == TimerPhase.Ended && old.id == current.id && old.CPs < current.CPs) {
		vars.timerModel.Reset();
		vars.timerModel.Start();

		vars.wait(20);
	}

	if (old.firstLapCPs != old.firstLapCPs || old.normalLapCPs != current.normalLapCPs) vars.message();
}

start {
	if (old.CPs != current.CPs && current.CPs == current.firstLapCPs ||
	    current.CPs - current.firstLapCPs > 0 && vars.onFirstCP) {
		vars.startTicks = current.raceTicks;
		return true;
	}
}

split {
	if (vars.CPsChanged) {
		if (old.playersInRace < current.playersInRace) return false;
		int expectedCP = old.CPs + 1, actualCP = current.CPs;

		if (expectedCP < actualCP) {
			vars.validLap = false;
			for (int i = expectedCP; i < actualCP; ++i)
				vars.timerModel.SkipSplit();
		}

		if (vars.onFirstCP) {
			vars.startTicks = current.raceTicks;
			if (!vars.onFinalSplit || !vars.validLap) return false;
		}

		return true;
	}
}

reset {
	if (old.raceTicks > current.raceTicks ||
	    vars.CPsChanged && current.CPs == 0 ||
	    vars.CPsChanged && vars.onFirstCP && (!vars.onFinalSplit || !vars.validLap) && timer.CurrentSplitIndex > 0) {
		vars.wait(500);
		vars.updateWatchers();
		return true;
	}
}

gameTime {
	return TimeSpan.FromSeconds((current.raceTicks - vars.startTicks) * 0.0078125);
}

isLoading {
	return true;
}

exit {
	vars.timerModel.Reset();
}

shutdown {
	timer.OnStart += vars.timerStart;
}