import { application } from "./application"

import FlashController from "./flash_controller"
import ModalController from "./modal_controller"
import VerificationController from "./verification_controller"
import ColorSyncController from "./color_sync_controller"

application.register("flash", FlashController)
application.register("modal", ModalController)
application.register("verification", VerificationController)
application.register("color-sync", ColorSyncController)
