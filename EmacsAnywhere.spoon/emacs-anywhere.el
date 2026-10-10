;;; emacs-anywhere.el --- Edit text from anywhere in Emacs -*- lexical-binding: t; -*-

;; Author: randall
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: convenience
;; URL: https://github.com/randall/emacs-anywhere

;;; Commentary:

;; Edit text from any macOS application in Emacs via Hammerspoon.
;;
;; This file is bundled with EmacsAnywhere.spoon and loaded automatically.
;; No Emacs configuration needed beyond (server-start).
;;
;; To customize, set variables in your Emacs config before triggering:
;;   (setq emacs-anywhere-hs-path "/usr/local/bin/hs")
;;   (setq emacs-anywhere-frame-parameters '((width . 100) (height . 30)))
;;   (setq emacs-anywhere-major-mode #'markdown-mode)
;;
;; Use `emacs-anywhere-mode-hook' for further buffer customization:
;;   (add-hook 'emacs-anywhere-mode-hook #'flyspell-mode)

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

(defcustom emacs-anywhere-major-mode #'text-mode
  "Major mode to use for emacs-anywhere buffers."
  :type 'function
  :group 'emacs-anywhere)

(defvar emacs-anywhere-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'emacs-anywhere-finish)
    (define-key map (kbd "C-c C-k") #'emacs-anywhere-abort)
    map)
  "Keymap for `emacs-anywhere-mode'.")

(define-minor-mode emacs-anywhere-mode
  "Minor mode for emacs-anywhere buffers.
Provides keybindings and a hook for customization."
  :lighter " Anywhere"
  :keymap emacs-anywhere-mode-map
  (when emacs-anywhere-mode
    ;; Don't add trailing newline - paste back exactly what user typed
    (setq-local require-final-newline nil)
    ;; Show help in header line (get app from frame parameter)
    (setq-local header-line-format
                (format " → %s  |  C-c C-c: finish  |  C-c C-k: abort"
                        (or (frame-parameter nil 'emacs-anywhere-app) "Unknown")))))

(defun emacs-anywhere--snapshot-frame-visibility ()
  "Return an alist of (FRAME . VISIBILITY) for every existing frame."
  (mapcar (lambda (f) (cons f (frame-visible-p f))) (frame-list)))

(defun emacs-anywhere--restore-frame-visibility (snapshot new-frame)
  "Restore visibility of frames in SNAPSHOT, leaving NEW-FRAME alone.
NSApp activation on macOS surfaces hidden/iconified frames when a new
frame is created.  This reverts each frame to its prior state."
  (dolist (cell snapshot)
    (let ((f (car cell))
          (vis (cdr cell)))
      (when (and (frame-live-p f) (not (eq f new-frame)))
        (pcase vis
          ('icon (iconify-frame f))
          ('nil  (make-frame-invisible f t)))))))

(defvar emacs-anywhere--parked-frames nil
  "Frames made invisible because Emacs was hidden when a session opened.
Unhiding an app on macOS shows every one of its windows, so while Emacs
is hidden the other frames are ordered out before activation.  The last
session to close puts them back and hides Emacs again.")

(defun emacs-anywhere--session-frames ()
  "Return the live emacs-anywhere frames."
  (filtered-frame-list
   (lambda (f) (frame-parameter f 'emacs-anywhere-file))))

(defun emacs-anywhere--park-frames ()
  "Make every visible graphic non-anywhere frame invisible and remember it.
Terminal frames, such as a daemon's initial frame, are left alone."
  (dolist (f (frame-list))
    (when (and (eq (frame-visible-p f) t)
               (display-graphic-p f)
               (not (frame-parameter f 'emacs-anywhere-file)))
      (push f emacs-anywhere--parked-frames)
      (make-frame-invisible f t))))

(defun emacs-anywhere--unpark-frames ()
  "Hide Emacs, then make the parked frames visible again.
Hiding first keeps the restored frames from appearing on screen; they
come back the next time Emacs itself is activated."
  (when emacs-anywhere--parked-frames
    (when (fboundp 'ns-hide-emacs)
      (ns-hide-emacs t))
    (dolist (f emacs-anywhere--parked-frames)
      (when (frame-live-p f)
        (make-frame-visible f)))
    (setq emacs-anywhere--parked-frames nil)))

(defun emacs-anywhere-open (file &optional app-name app-bundle-id mouse-x mouse-y
                                 emacs-hidden)
  "Open FILE in a new frame for editing.
APP-NAME is the name of the source application (for display).
APP-BUNDLE-ID is the bundle ID of the source application (for reliable lookup).
MOUSE-X and MOUSE-Y are the cursor position for frame placement.
EMACS-HIDDEN non-nil means the Emacs app is hidden (Cmd-H); its other
frames are then parked so that activation shows only the new frame.

Snapshots existing frames' visibility before creating the new frame and
restores it shortly after, so that minimized or hidden frames are not
surfaced as a side effect of NSApp activation."
  (when emacs-hidden
    (emacs-anywhere--park-frames))
  (let* ((snapshot (emacs-anywhere--snapshot-frame-visibility))
         (frame-params
          (append
           `((name . ,(or (cdr (assq 'name emacs-anywhere-frame-parameters))
                          "emacs-anywhere"))
             ;; Force a NS graphic frame; without this, `make-frame' called
             ;; from a daemon falls back to a TTY frame and errors with
             ;; "Unknown terminal type".
             (window-system . ns)
             (width  . ,(or (cdr (assq 'width  emacs-anywhere-frame-parameters)) 80))
             (height . ,(or (cdr (assq 'height emacs-anywhere-frame-parameters)) 20))
             (emacs-anywhere-file      . ,file)
             (emacs-anywhere-app       . ,(or app-name "Unknown"))
             (emacs-anywhere-bundle-id . ,(or app-bundle-id app-name)))
           (when mouse-x `((left . ,mouse-x)))
           (when mouse-y `((top  . ,mouse-y)))))
         (frame (make-frame frame-params)))

    (select-frame frame)
    (raise-frame frame)

    (with-selected-frame frame
      (find-file file)
      (emacs-anywhere--setup-buffer))

    (select-frame-set-input-focus frame)

    (run-at-time 0.05 nil
                 #'emacs-anywhere--restore-frame-visibility
                 snapshot frame)))

(defun emacs-anywhere--setup-buffer ()
  "Set up the emacs-anywhere buffer."
  (funcall emacs-anywhere-major-mode)

  ;; Exclude from recentf (use pattern, not individual filenames)
  (when (bound-and-true-p recentf-mode)
    (add-to-list 'recentf-exclude "^/tmp/emacs-anywhere/"))

  ;; Put cursor at end of buffer
  (goto-char (point-max))

  ;; Enable minor mode (sets up keybindings, header-line, etc.)
  (emacs-anywhere-mode 1))

(defun emacs-anywhere-finish ()
  "Save the buffer, notify Hammerspoon, and close the frame."
  (interactive)
  (let ((file (frame-parameter nil 'emacs-anywhere-file)))
    (when file
      ;; Save the file
      (save-buffer)

      ;; Notify Hammerspoon to paste the content
      (emacs-anywhere--notify-hammerspoon)

      ;; Clean up
      (emacs-anywhere--cleanup))))

(defun emacs-anywhere-abort ()
  "Abort editing without saving, and delete the temp file."
  (interactive)
  (let ((file (frame-parameter nil 'emacs-anywhere-file)))
    ;; Notify Hammerspoon to refocus original app (without pasting)
    (emacs-anywhere--notify-hammerspoon-abort)
    ;; Clean up
    (emacs-anywhere--cleanup)
    ;; On finish Hammerspoon deletes the file after reading it; on abort
    ;; nothing reads it, so it is deleted here.
    (when (and file (file-exists-p file))
      (delete-file file))))

(defun emacs-anywhere--notify-hammerspoon ()
  "Tell Hammerspoon to paste the content back."
  (let* ((file (frame-parameter nil 'emacs-anywhere-file))
         (bundle-id (frame-parameter nil 'emacs-anywhere-bundle-id))
         (cmd (format "%s -c 'spoon.EmacsAnywhere:finish(\"%s\", \"%s\")'"
                      emacs-anywhere-hs-path
                      file
                      bundle-id)))
    (call-process-shell-command cmd nil 0)))

(defun emacs-anywhere--notify-hammerspoon-abort ()
  "Tell Hammerspoon to refocus original app without pasting."
  (let* ((bundle-id (frame-parameter nil 'emacs-anywhere-bundle-id))
         (cmd (format "%s -c 'spoon.EmacsAnywhere:abort(\"%s\")'"
                      emacs-anywhere-hs-path
                      bundle-id)))
    (call-process-shell-command cmd nil 0)))

(defun emacs-anywhere--cleanup ()
  "Clean up the emacs-anywhere state."
  (let ((buf (current-buffer))
        (frame (selected-frame)))

    ;; Mark buffer as unmodified to skip confirmation (only this buffer)
    (with-current-buffer buf
      (set-buffer-modified-p nil))

    ;; Restore parked frames before deleting this one: deleting the sole
    ;; visible frame is an error.
    (when (equal (emacs-anywhere--session-frames) (list frame))
      (emacs-anywhere--unpark-frames))

    ;; Kill buffer and frame
    (kill-buffer buf)
    (when (frame-live-p frame)
      (delete-frame frame))))

(provide 'emacs-anywhere)
;;; emacs-anywhere.el ends here
