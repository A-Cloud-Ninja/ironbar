use super::{CustomWidget, CustomWidgetContext};
use crate::build;
use crate::dynamic_value::dynamic_string;
use crate::image::ImageProvider;
use gtk::prelude::*;
use gtk::Image;
use serde::Deserialize;

#[derive(Debug, Deserialize, Clone)]
pub struct ImageWidget {
    name: Option<String>,
    class: Option<String>,
    src: String,
    #[serde(default = "default_size")]
    size: i32,
}

const fn default_size() -> i32 {
    32
}

impl CustomWidget for ImageWidget {
    type Widget = Image;

    fn into_widget(self, context: CustomWidgetContext) -> Self::Widget {
        let gtk_image = build!(self, Self::Widget);

        {
            let gtk_image = gtk_image.clone();
            let icon_theme = context.icon_theme.clone();

            dynamic_string(&self.src, move |src| {
                ImageProvider::parse(&src, &icon_theme, self.size)
                    .map(|image| image.load_into_image(gtk_image.clone()));

                Continue(true)
            });
        }

        gtk_image
    }
}
