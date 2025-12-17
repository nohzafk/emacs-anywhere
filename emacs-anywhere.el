;;; emacs-anywhere.el --- Edit text from anywhere in Emacs -*- lexical-binding: t; -*-

;; Author: randall
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: convenience
;; URL: https://github.com/randall/emacs-anywhere

;;; Commentary:

;; Edit text from any macOS application in Emacs via Hammerspoon.
;;
;; Usage:
;;   1. Install the EmacsAnywhere.spoon in Hammerspoon
;;   2. Add this package to your Emacs config
;;   3. Bind a hotkey in Hammerspoon to trigger EmacsAnywhere:start()
;;   4. Press the hotkey in any app to edit text in Emacs

;;; Code:

(defgroup emacs-anywhere nil
  "Edit text from anywhere in Emacs."
  :group 'convenience
  :prefix "emacs-anywhere-")

(defcustom emacs-anywhere-hs-path "/opt/homebrew/bin/hs"
  "Path to Hammerspoon CLI."
  :type 'string
  :group 'emacs-anywhere)

(defcustom emacs-anywhere-frame-parameters
  '((name . "emacs-anywhere")
    (width . 80)
    (height . 20)
    (top . 100)
    (left . 100))
  "Frame parameters for the emacs-anywhere frame."
  :type 'alist
  :group 'emacs-anywhere)

(defvar emacs-anywhere--current-file nil
  "The current temp file being edited.")

(defvar emacs-anywhere--frame nil
  "The emacs-anywhere frame.")

(defvar emacs-anywhere--source-app nil
  "The app that triggered emacs-anywhere.")

(defun emacs-anywhere-open (file &optional app-name mouse-x mouse-y)
  "Open FILE in a new frame for editing.
APP-NAME is the name of the source application.
MOUSE-X and MOUSE-Y are the cursor position for frame placement."
  (setq emacs-anywhere--current-file file)
  (setq emacs-anywhere--source-app (or app-name "Unknown"))

  ;; Build frame parameters with position
  (let ((frame-params (copy-alist emacs-anywhere-frame-parameters)))
    (when mouse-x
      (setf (alist-get 'left frame-params) mouse-x))
    (when mouse-y
      (setf (alist-get 'top frame-params) mouse-y))

    ;; Create a new frame
    (setq emacs-anywhere--frame (make-frame frame-params)))
  (select-frame emacs-anywhere--frame)
  (raise-frame emacs-anywhere--frame)

  ;; Open the file
  (find-file file)

  ;; Set up the buffer
  (emacs-anywhere--setup-buffer)

  ;; Focus the frame
  (select-frame-set-input-focus emacs-anywhere--frame))

(defun emacs-anywhere--setup-buffer ()
  "Set up the emacs-anywhere buffer."
  ;; Use a sensible default mode
  (when (eq major-mode 'fundamental-mode)
    (text-mode))

  ;; Exclude from recentf (use pattern, not individual filenames)
  (when (bound-and-true-p recentf-mode)
    (add-to-list 'recentf-exclude "^/tmp/emacs-anywhere/"))

  ;; Don't add trailing newline - paste back exactly what user typed
  (setq-local require-final-newline nil)

  ;; Put cursor at end of buffer
  (goto-char (point-max))

  ;; Add keybindings
  (local-set-key (kbd "C-c C-c") #'emacs-anywhere-finish)
  (local-set-key (kbd "C-c C-k") #'emacs-anywhere-abort)

  ;; Show help in header line
  (setq-local header-line-format
              (format " → %s  |  C-c C-c: finish  |  C-c C-k: abort"
                      emacs-anywhere--source-app)))

(defun emacs-anywhere-finish ()
  "Save the buffer, notify Hammerspoon, and close the frame."
  (interactive)
  (when emacs-anywhere--current-file
    ;; Save the file
    (save-buffer)

    ;; Notify Hammerspoon to paste the content
    (emacs-anywhere--notify-hammerspoon)

    ;; Clean up
    (emacs-anywhere--cleanup)))

(defun emacs-anywhere-abort ()
  "Abort editing without saving."
  (interactive)
  ;; Notify Hammerspoon to refocus original app (without pasting)
  (emacs-anywhere--notify-hammerspoon-abort)
  ;; Clean up
  (emacs-anywhere--cleanup))

(defun emacs-anywhere--notify-hammerspoon ()
  "Tell Hammerspoon to paste the content back."
  (let ((cmd (format "%s -c 'spoon.EmacsAnywhere:finish()'"
                     emacs-anywhere-hs-path)))
    (call-process-shell-command cmd nil 0)))

(defun emacs-anywhere--notify-hammerspoon-abort ()
  "Tell Hammerspoon to refocus original app without pasting."
  (let ((cmd (format "%s -c 'spoon.EmacsAnywhere:abort()'"
                     emacs-anywhere-hs-path)))
    (call-process-shell-command cmd nil 0)))

(defun emacs-anywhere--cleanup ()
  "Clean up the emacs-anywhere state."
  (let ((buf (current-buffer))
        (frame emacs-anywhere--frame))

    ;; Reset state
    (setq emacs-anywhere--current-file nil)
    (setq emacs-anywhere--frame nil)

    ;; Mark buffer as unmodified to skip confirmation (only this buffer)
    (with-current-buffer buf
      (set-buffer-modified-p nil))

    ;; Kill buffer and frame
    (kill-buffer buf)
    (when (and frame (frame-live-p frame))
      (delete-frame frame))))

(provide 'emacs-anywhere)
;;; emacs-anywhere.el ends here
