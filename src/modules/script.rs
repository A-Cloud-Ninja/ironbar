use crate::config::CommonConfig;
use crate::modules::{Module, ModuleInfo, ModuleUpdateEvent, ModuleWidget, WidgetContext};
use crate::script::{OutputStream, Script, ScriptMode};
use crate::try_send;
use color_eyre::{Help, Report, Result};
use gtk::prelude::*;
use gtk::Label;
use serde::Deserialize;
use tokio::spawn;
use tokio::sync::mpsc::{Receiver, Sender};
use tracing::error;

#[derive(Debug, Deserialize, Clone)]
pub struct ScriptModule {
    /// Path to script to execute.
    cmd: String,
    /// Script execution mode
    #[serde(default = "default_mode")]
    mode: ScriptMode,
    /// Time in milliseconds between executions.
    #[serde(default = "default_interval")]
    interval: u64,

    #[serde(flatten)]
    pub common: Option<CommonConfig>,
}

/// `Mode::Poll`
const fn default_mode() -> ScriptMode {
    ScriptMode::Poll
}

/// 5000ms
const fn default_interval() -> u64 {
    5000
}

impl From<&ScriptModule> for Script {
    fn from(module: &ScriptModule) -> Self {
        Self {
            mode: module.mode,
            cmd: module.cmd.clone(),
            interval: module.interval,
        }
    }
}

impl Module<Label> for ScriptModule {
    type SendMessage = String;
    type ReceiveMessage = ();

    fn name() -> &'static str {
        "script"
    }

    fn spawn_controller(
        &self,
        _info: &ModuleInfo,
        tx: Sender<ModuleUpdateEvent<Self::SendMessage>>,
        _rx: Receiver<Self::ReceiveMessage>,
    ) -> Result<()> {
        let script: Script = self.into();

        spawn(async move {
            script.run(None, move |out, _| match out {
               OutputStream::Stdout(stdout) => {
                   try_send!(tx, ModuleUpdateEvent::Update(stdout));
               },
               OutputStream::Stderr(stderr) => {
                   error!("{:?}", Report::msg(stderr)
                                    .wrap_err("Watched script error:")
                                    .suggestion("Check the path to your script")
                                    .suggestion("Check the script for errors")
                                    .suggestion("If you expect the script to write to stderr, consider redirecting its output to /dev/null to suppress these messages"));
               }
           }).await;
        });

        Ok(())
    }

    fn into_widget(
        self,
        context: WidgetContext<Self::SendMessage, Self::ReceiveMessage>,
        info: &ModuleInfo,
    ) -> Result<ModuleWidget<Label>> {
        let label = Label::builder().use_markup(true).build();
        label.set_angle(info.bar_position.get_angle());

        {
            let label = label.clone();
            context.widget_rx.attach(None, move |s| {
                label.set_markup(s.as_str());
                Continue(true)
            });
        }

        Ok(ModuleWidget {
            widget: label,
            popup: None,
        })
    }
}
