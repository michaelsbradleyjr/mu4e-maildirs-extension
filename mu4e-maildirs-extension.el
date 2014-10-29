;;; mu4e-maildirs-extension.el --- Show mu4e maildirs summary in mu4e-main-view

;; This file is not part of Emacs

;; Copyright (C) 2013 Andreu Gil Pàmies

;; Filename: mu4e-maildirs-extension.el
;; Version: 0.1
;; Author: Andreu Gil Pàmies <agpchil@gmail.com>
;; Created: 22-07-2013
;; Description: Show mu4e maildirs summary in mu4e-main-view with unread and
;; total mails for each maildir
;; URL: http://github.com/agpchil/mu4e-maildirs-extension

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Usage:
;; (require 'mu4e-maildirs-extension)
;; (mu4e-maildirs-extension)

;;; Commentary:

;;; Code:
(require 'deferred)
;; (require 'enotify)
;; (require 'enotify-tdd)
(require 'mu4e)

;; (enotify-minor-mode t)

(defgroup mu4e-maildirs-extension nil
  "Show mu4e maildirs summary in mu4e-main-view with unread and
total mails for each maildir."
  :link '(url-link "https://github.com/agpchil/mu4e-maildirs-extension")
  :prefix "mu4e-maildirs-extension-"
  :group 'external)

(defcustom mu4e-maildirs-extension-action-key "u"
  "Key shortcut to update index and cache."
  :group 'mu4e-maildirs-extension
  :type '(key-sequence))

(defcustom mu4e-maildirs-extension-action-text "\t* [u]pdate index & cache\n"
  "Action text to display for updating the index and cache.
If set to 'Don't Display (nil)' it won't be displayed."
  :group 'mu4e-maildirs-extension
  :type '(choice string (const :tag "Don't Display" nil)))

(defcustom mu4e-maildirs-sync-action-key "F"
  "Key shortcut to force offlineimap \"daemon\" to sync."
  :group 'mu4e-maildirs-extension
  :type '(key-sequence))

(defcustom mu4e-maildirs-sync-action-text "\t* [F]orce offlineimap to sync\n"
  "Action text to display for forcing offlineimap to sync.
If set to 'Don't Display (nil)' it won't be displayed."
  :group 'mu4e-maildirs-extension
  :type '(choice string (const :tag "Don't Display" nil)))

(defcustom mu4e-maildirs-extension-count-command-format
  "mu find %s maildir:'%s' --fields 'i' --skip-dups 2>/dev/null |wc -l |tr -d '\n'"
  "The command to count a maildir.  [Most people won't need to edit this]."
  :group 'mu4e-maildirs-extension
  :type '(string))

(defcustom mu4e-maildirs-extension-custom-list nil
  "Custom list of folders to show."
  :group 'mu4e-maildirs-extension
  :type '(repeat string))
  ;; :type '(sexp))

(defcustom mu4e-maildirs-extension-insert-before-str "\n  Misc"
  "The place where the maildirs summary should be inserted."
  :group 'mu4e-maildirs-extension
  :type '(choice (const :tag "Basics" "\n  Basics")
                 (const :tag "Bookmarks" "\n  Bookmarks")
                 (const :tag "Misc" "\n  Misc")))

(defcustom mu4e-maildirs-extension-maildir-separator "+"
  "The separator for each top level mail direcotry."
  :group 'mu4e-maildirs-extension
  :type '(string))

(defcustom mu4e-maildirs-extension-propertize-func
  #'mu4e-maildirs-extension-propertize-handler
  "The function to format the maildir info.
Default dispays as '| maildir_name (unread/total)'."
  :group 'mu4e-maildirs-extension
  :type '(function))

(defcustom mu4e-maildirs-extension-submaildir-indent 2
  "Indentation of submaildirs."
  :group 'mu4e-maildirs-extension
  :type '(integer))

(defcustom mu4e-maildirs-extension-submaildir-separator "|"
  "The separator for each sub-level mail directory."
  :group 'mu4e-maildirs-extension
  :type '(string))

(defcustom mu4e-maildirs-extension-title "  Maildirs\n"
  "The title label for the maildirs extension."
  :group 'mu4e-maildirs-extension
  :type '(choice string (const :tag "Don't Display" nil)))

(defface mu4e-maildirs-extension-maildir-face
  '((t :inherit mu4e-header-face))
  "Face for a normal maildir."
  :group 'mu4e-maildirs-extension)

(defface mu4e-maildirs-extension-maildir-unread-face
  '((t :inherit mu4e-unread-face))
  "Face for a maildir containing unread items."
  :group 'mu4e-maildirs-extension)

(defvar mu4e-maildirs-extension-start-point nil)

(defvar mu4e-maildirs-extension-end-point nil)

(defvar mu4e-maildirs-extension-cached-maildirs-data nil)

(defvar mu4e-maildirs-extension-buffer-name mu4e~main-buffer-name)

(defvar mu4e-maildirs-extension-index-updated-func
  'mu4e-maildirs-extension-index-updated-handler)

(defvar mu4e-maildirs-extension-main-view-func
  'mu4e-maildirs-extension-main-view-handler)

(defvar mu4e-maildirs-extension-index-updated-func-deferred
  'mu4e-maildirs-extension-index-updated-handler-deferred)

(defvar mu4e-maildirs-extension-main-view-func-deferred
  'mu4e-maildirs-extension-main-view-handler-deferred)

;; (defun mu4e-maildirs-extension-index-updated-handler ()
;;   "Handler for `mu4e-index-updated-hook'."
;;   (setq mu4e-maildirs-extension-cached-maildirs-data nil)
;;   (when (equal (buffer-name) mu4e-maildirs-extension-buffer-name)
;;     (mu4e-maildirs-extension-update)))

(defun mu4e-maildirs-extension-index-updated-handler-deferred ()
  "Handler for `mu4e-index-updated-hook'."
  (when (equal (buffer-name) mu4e-maildirs-extension-buffer-name)
   (setq mu4e-maildirs-extension-cached-maildirs-data nil))
  (when (equal (buffer-name) mu4e-maildirs-extension-buffer-name)
    (deferred:$
      (deferred:next
        (lambda () (mu4e-maildirs-extension-update-deferred)))
      (deferred:nextc it
        (lambda ()
          (mu4e-maildirs-extension-imap-notify-clear))))))

;; (defun mu4e-maildirs-extension-main-view-handler ()
;;   "Handler for `mu4e-main-view-mode-hook'."
;;   (setq mu4e-maildirs-extension-start-point nil)
;;   (mu4e-maildirs-extension-update))

(defun mu4e-maildirs-extension-main-view-handler-deferred ()
  "Handler for `mu4e-main-view-mode-hook'."
  (setq mu4e-maildirs-extension-start-point nil)
  (deferred:$
    (deferred:next
      (lambda ()
        (mu4e-maildirs-extension-update-deferred)))
    (deferred:nextc it
      (lambda ()
        (mu4e-maildirs-extension-imap-notify :warning)
        ;; (setq mu4e-maildirs-extension-cached-maildirs-data nil)
        ;; (mu4e-maildirs-extension-update-deferred)
        ;; (mu4e-maildirs-extension-force-update)
        ))
    (deferred:nextc it
      (lambda ()
        (mu4e-maildirs-extension-imap-notify-clear)))))

;; (defun mu4e-maildirs-extension-execute-count (mdir &optional opts)
;;   "Execute the count command for a MDIR with optional OPTS."
;;   (let* ((mu-opts (if opts opts ""))
;;          (cmd (format mu4e-maildirs-extension-count-command-format
;;                       mu-opts
;;                       mdir)))
;;     (string-to-number (replace-regexp-in-string "![0-9]"
;;                                                 ""
;;                                                 (shell-command-to-string cmd)))))

(defun mu4e-maildirs-extension-execute-count-deferred (mdir &optional opts)
  "Execute the count command for a MDIR with optional OPTS."
  (lexical-let* ((mu-opts (if opts opts ""))
                 (cmd (format mu4e-maildirs-extension-count-command-format
                              mu-opts
                              mdir)))
    (deferred:$
      (deferred:process "bash" "-c" cmd)
      (deferred:nextc it
        (lambda (str)
          (string-to-number (replace-regexp-in-string "![0-9]"
                                                      ""
                                                      str)))))))

(defun mu4e-maildirs-extension-get-parents (path)
  "Get the maildir parents of maildir PATH name.
Given PATH \"/foo/bar/alpha\" will return '(\"/foo\" \"/bar\")."
  (setq path (replace-regexp-in-string "^/" "" path))
  (setq path (replace-regexp-in-string "\\/\\*$" "" path))
  (butlast (split-string path "/" t)))

(defun mu4e-maildirs-extension-get-maildirs ()
  "Get maildirs."
  (let ((maildirs (or mu4e-maildirs-extension-custom-list
                      (mu4e-get-maildirs)))
        (view-maildirs nil)
        (path-history nil))

    (mapc #'(lambda (name)
              (let ((parents (mu4e-maildirs-extension-get-parents name))
                    (path nil))
                (mapc #'(lambda (parent-name)
                          (setq path (concat path "/" parent-name))
                          (unless (assoc path path-history)
                            (add-to-list 'view-maildirs (format "%s/*" path))))
                      parents))

              (add-to-list 'view-maildirs name))
          maildirs)
    (reverse view-maildirs)))

;; (defun mu4e-maildirs-extension-fetch ()
;;   "Fetch maildirs data."
;;   (let ((data nil))
;;     (mapc
;;      #'(lambda (maildir)
;;          (let ((item nil)
;;                (level (length (mu4e-maildirs-extension-get-parents maildir)))
;;                (is-parent-p (string-match "\\/\\*$" maildir)))
;;            (setq item (plist-put item
;;                                  :name
;;                                  (car (reverse (split-string (replace-regexp-in-string
;;                                                               "\\/\\*$" "" maildir) "/")))))
;;            (setq item (plist-put item
;;                                  :level
;;                                  level))
;;            (setq item (plist-put item
;;                                  :path
;;                                  maildir))
;;            (setq item (plist-put item
;;                                  :separator
;;                                  (if (or is-parent-p (equal level 0))
;;                                      mu4e-maildirs-extension-maildir-separator
;;                                    mu4e-maildirs-extension-submaildir-separator)))
;;            (setq item (plist-put item
;;                                  :indent
;;                                  (make-string (* mu4e-maildirs-extension-submaildir-indent level)
;;                                               32)))
;;            (setq item (plist-put item
;;                                  :total
;;                                  (mu4e-maildirs-extension-execute-count maildir)))
;;            (setq item (plist-put item
;;                                  :unread
;;                                  (mu4e-maildirs-extension-execute-count maildir "flag:unread")))
;;            (add-to-list 'data item)))
;;      (mu4e-maildirs-extension-get-maildirs))
;;     (reverse data)))

(defun mu4e-maildirs-extension-fetch-deferred ()
  "Fetch maildirs data."
  (lexical-let ((maildirs (mu4e-maildirs-extension-get-maildirs))
                (data nil))
    (deferred:$
      (deferred:parallel
        (map 'list
             (lambda (dir)
               (lexical-let ((dir dir))
                 (lambda ()
                   (deferred:$
                     (deferred:next
                       (lambda ()
                         (deferred:$
                           (deferred:parallel
                             (lambda ()
                               (mu4e-maildirs-extension-execute-count-deferred dir "\\(NOT flag:trashed\\)"))
                             (lambda ()
                               (mu4e-maildirs-extension-execute-count-deferred dir "flag:unread")))
                           (deferred:nextc it
                             (lambda (tup) (list dir tup))))))))))
             maildirs))
      (deferred:nextc it
        (lambda (tups)
          (mapc
           #'(lambda (tup)
               (lexical-let ((dir (first tup))
                             (ctup (second tup)))
                 (lexical-let ((total (first ctup))
                               (unread (second ctup))
                               (item nil)
                               (level (length (mu4e-maildirs-extension-get-parents dir)))
                               (is-parent-p (string-match "\\/\\*$" dir)))
                   (lexical-let*
                       ((item (plist-put item
                                         :name
                                         (car (reverse (split-string (replace-regexp-in-string
                                                                      "\\/\\*$" "" dir) "/")))))
                        (item (plist-put item
                                         :level
                                         level))
                        (item (plist-put item
                                         :path
                                         dir))
                        (item (plist-put item
                                         :separator
                                         (if (or is-parent-p (equal level 0))
                                             mu4e-maildirs-extension-maildir-separator
                                           mu4e-maildirs-extension-submaildir-separator)))
                        (item (plist-put item
                                         :indent
                                         (make-string (* mu4e-maildirs-extension-submaildir-indent level)
                                                      32)))
                        (item (plist-put item
                                         :total
                                         total))
                        (item (plist-put item
                                         :unread
                                         unread)))
                     (push item data)))))
           tups)
          (reverse data))))))

(defun mu4e-maildirs-extension-propertize-handler (item)
  "Propertize the maildir text using ITEM plist."
  (propertize (format "%s\t%s%s %s (%s/%s)\n"
                      (if (equal (plist-get item :level) 0) "\n" "")
                      (plist-get item :indent)
                      (plist-get item :separator)
                      (plist-get item :name)
                      (plist-get item :unread)
                      (plist-get item :total))
              'face (cond
                     ((> (plist-get item :unread) 0) 'mu4e-maildirs-extension-maildir-unread-face)
                     (t            'mu4e-maildirs-extension-maildir-face))))

;; (defun mu4e-maildirs-extension-fetch-maybe ()
;;   "Fetch data if no cache."
;;   (unless mu4e-maildirs-extension-cached-maildirs-data
;;     (setq mu4e-maildirs-extension-cached-maildirs-data
;;           (mu4e-maildirs-extension-fetch))))

(defun mu4e-maildirs-extension-fetch-maybe-deferred ()
  "Fetch data if no cache."
  (deferred:$
    (deferred:next
      (lambda ()
        (if mu4e-maildirs-extension-cached-maildirs-data
            mu4e-maildirs-extension-cached-maildirs-data
          (mu4e-maildirs-extension-fetch-deferred))))
    (deferred:nextc it
      (lambda (data)
        (setq mu4e-maildirs-extension-cached-maildirs-data
              data)))))

(defun mu4e-maildirs-extension-action-str (str &optional func-or-shortcut)
  "Custom action without using [.] in STR.
If FUNC-OR-SHORTCUT is non-nil and if it is a function, call it
when STR is clicked (using RET or mouse-2); if FUNC-OR-SHORTCUT is
a string, execute the corresponding keyboard action when it is
clicked."
  (let ((newstr str)
        (map (make-sparse-keymap))
        (func (if (functionp func-or-shortcut)
                  func-or-shortcut
                (if (stringp func-or-shortcut)
                    (lexical-let ((macro func-or-shortcut))
                      (lambda()(interactive)
                        (execute-kbd-macro macro)))))))
    (define-key map [mouse-2] func)
    (define-key map (kbd "RET") func)
    (put-text-property 0 (length newstr) 'keymap map newstr)
    (put-text-property (string-match "[^\n\t\s-].+$" newstr)
                       (- (length newstr) 1) 'mouse-face 'highlight newstr)
    newstr))

;; (defun mu4e-maildirs-extension-update ()
;;   "Insert maildirs summary in `mu4e-main-view'."
;;   (mu4e-maildirs-extension-fetch-maybe)
;;
;;   (let ((buf (get-buffer mu4e-maildirs-extension-buffer-name))
;;         (maildirs mu4e-maildirs-extension-cached-maildirs-data)
;;         (inhibit-read-only t))
;;     (when buf
;;       (with-current-buffer buf
;;         (if mu4e-maildirs-extension-start-point
;;             (delete-region mu4e-maildirs-extension-start-point
;;                            mu4e-maildirs-extension-end-point)
;;           (setq mu4e-maildirs-extension-start-point
;;                 (search-backward mu4e-maildirs-extension-insert-before-str)))
;;
;;         (goto-char mu4e-maildirs-extension-start-point)
;;
;;         (when mu4e-maildirs-extension-title
;;           (insert "\n"
;;                   (propertize mu4e-maildirs-extension-title 'face 'mu4e-title-face)))
;;
;;         (when mu4e-maildirs-extension-action-text
;;           (insert "\n"
;;                   (mu4e~main-action-str mu4e-maildirs-extension-action-text
;;                                         mu4e-maildirs-extension-action-key)))
;;
;;         (define-key mu4e-main-mode-map
;;           mu4e-maildirs-extension-action-key
;;           'mu4e-maildirs-extension-force-update)
;;
;;         (mapc #'(lambda (item)
;;                   (insert (mu4e-maildirs-extension-action-str
;;                            (funcall mu4e-maildirs-extension-propertize-func item)
;;                            `(lambda ()
;;                               (interactive)
;;                               (mu4e~headers-jump-to-maildir ,(plist-get item :path))))))
;;               maildirs)
;;
;;         (setq mu4e-maildirs-extension-end-point (point))
;;         (goto-char (point-min))))))

(defun mu4e-maildirs-extension-update-deferred ()
  "Insert maildirs summary in `mu4e-main-view'."
  (deferred:$
    (deferred:next
      (lambda ()
        (mu4e-maildirs-extension-fetch-maybe-deferred)))
    (deferred:nextc it
      (lambda ()
        (let ((buf (get-buffer mu4e-maildirs-extension-buffer-name))
              ;; (maildirs mu4e-maildirs-extension-cached-maildirs-data)
              (inhibit-read-only t))
          (lexical-let ((maildirs mu4e-maildirs-extension-cached-maildirs-data))
            (when buf
              (with-current-buffer buf
                (let ((curr-point (point))
                      ;; (curr-posit (what-cursor-position))
                      ;; (curr-win (current-window-configuration))
                      )
                  (window-configuration-to-register ?r)
                  (if mu4e-maildirs-extension-start-point
                      (delete-region mu4e-maildirs-extension-start-point
                                     mu4e-maildirs-extension-end-point)
                    (setq mu4e-maildirs-extension-start-point
                          (search-backward mu4e-maildirs-extension-insert-before-str)))

                  (goto-char mu4e-maildirs-extension-start-point)

                  (when mu4e-maildirs-extension-title
                    (insert "\n"
                            (propertize mu4e-maildirs-extension-title 'face 'mu4e-title-face)))

                  (when mu4e-maildirs-extension-action-text
                    (insert "\n"
                            (mu4e~main-action-str mu4e-maildirs-extension-action-text
                                                  mu4e-maildirs-extension-action-key)))

                  (when mu4e-maildirs-sync-action-text
                    (insert (mu4e~main-action-str mu4e-maildirs-sync-action-text
                                                  mu4e-maildirs-sync-action-key)))

                  (define-key mu4e-main-mode-map
                    mu4e-maildirs-extension-action-key
                    'mu4e-maildirs-extension-force-update)

                  (define-key mu4e-main-mode-map
                    mu4e-maildirs-sync-action-key
                    'mu4e-maildirs-extension-force-sync)

                  (mapc #'(lambda (item)
                            (insert (mu4e-maildirs-extension-action-str
                                     (funcall mu4e-maildirs-extension-propertize-func item)
                                     `(lambda ()
                                        (interactive)
                                        (mu4e~headers-jump-to-maildir ,(plist-get item :path))))))
                        maildirs)

                  (setq mu4e-maildirs-extension-end-point (point))
                  (jump-to-register ?r)
                  (goto-char curr-point)
                  ;; (scroll-up 1)
                  (goto-char curr-point))))))))))

(defvar mu4e-maildirs-extension-redefine-info-handler nil)

(defun mu4e-maildirs-extension-force-update ()
  "Clear cache and insert maildirs summary."
  (interactive)
  (mu4e-message "Updating index & cache...")
  (progn
    (when (not mu4e-maildirs-extension-redefine-info-handler)
      (progn
        (setq mu4e-maildirs-extension-redefine-info-handler t)
        (defun mu4e-info-handler (info)
          "Handler function for (:info ...) sexps received from the server process."
          (let ((type (plist-get info :info)))
            (cond
             ((eq type 'add) t) ;; do nothing
             ((eq type 'index)
              (if (eq (plist-get info :status) 'running)
                  (mu4e-index-message "Indexing... processed %d, updated %d"
                                      (plist-get info :processed) (plist-get info :updated))
                (progn
                  (mu4e-index-message
                   "Indexing completed; processed %d, updated %d, cleaned-up %d"
                   (plist-get info :processed) (plist-get info :updated)
                   (plist-get info :cleaned-up))
                  ;; (unless (zerop (plist-get info :updated))
                  ;;   (run-hooks 'mu4e-index-updated-hook))
                  ;; always run the hooks, so flag related changes are picked up,
                  ;; i.e. even though the index didn't actually change
                  (run-hooks 'mu4e-index-updated-hook))))
             ((plist-get info :message)
              (mu4e-index-message "%s" (plist-get info :message))))))))
    (mu4e-maildirs-extension-imap-notify :failure)
    (mu4e-update-index)))

(define-key mu4e-headers-mode-map (kbd "C-c M-u") 'mu4e-maildirs-extension-force-update)
(define-key mu4e-view-mode-map (kbd "C-c M-u") 'mu4e-maildirs-extension-force-update)

(defun mu4e-maildirs-extension-force-sync ()
  "Force the offlineimap process to sync."
  (interactive)
  (mu4e-message "Forcing offlineimap to sync...")
  (deferred:$
    (deferred:process "bash" "-c" "kill -SIGUSR1 `cat ~/.offlineimap/pid`")
    (deferred:nextc it
      (lambda ()
        (mu4e-message "Forced offlineimap to sync")))))

(define-key mu4e-headers-mode-map (kbd "C-c M-F") 'mu4e-maildirs-extension-force-sync)
(define-key mu4e-view-mode-map (kbd "C-c M-F") 'mu4e-maildirs-extension-force-sync)

;;;###autoload
(defun mu4e-maildirs-extension ()
  "Initialize."
  ;; (remove-hook 'mu4e-index-updated-hook mu4e-maildirs-extension-index-updated-func)
  ;; (add-hook 'mu4e-index-updated-hook mu4e-maildirs-extension-index-updated-func)

  ;; (remove-hook 'mu4e-main-mode-hook mu4e-maildirs-extension-main-view-func)
  ;; (add-hook 'mu4e-main-mode-hook mu4e-maildirs-extension-main-view-func)

  (remove-hook 'mu4e-index-updated-hook mu4e-maildirs-extension-index-updated-func-deferred)
  (add-hook 'mu4e-index-updated-hook mu4e-maildirs-extension-index-updated-func-deferred)

  (remove-hook 'mu4e-main-mode-hook mu4e-maildirs-extension-main-view-func-deferred)
  (add-hook 'mu4e-main-mode-hook mu4e-maildirs-extension-main-view-func-deferred))

;; custom mode line notifications
(defun enotify-start-server-1 (port)
  "Starts the Enotify notification service, listening on localhost"

  nil

  ;; (setq enotify-connection (make-network-process :name (symbol-value 'enotify-process-name)
  ;;                                                :server t
  ;;                                                :family 'ipv4
  ;;                                                :host 'local
  ;;                                                :service port
  ;;                                                :filter 'enotify-message-filter))
  ;; (process-kill-without-query (symbol-value 'enotify-connection))

  )

;; (setq enotify/tdd:blink-delay 1.0)
;; (enotify/plugin:register "imap" :handler 'enotify/tdd:report-message-handler :mouse-1-handler (lambda ()))



(defun mu4e-maildirs-extension-imap-notify (&optional which-face)
  "notifies"

  nil

  ;; (mu4e-maildirs-extension-imap-notify-clear)
  ;; (enotify-mode-line-update-notification
  ;;  "imap"
  ;;  (list :text "mu"
  ;;        :face (or which-face :success)))
  ;; (enotify/tdd::set-blink "imap")

  )

(defun mu4e-maildirs-extension-imap-notify-clear ()
  "clears the notification"

  nil

  ;; (when (getf (enotify-mode-line-notification "imap") :text)
  ;;   (enotify/tdd::unset-blink "imap")
  ;;   (remhash "imap" enotify/tdd::blink-table)
  ;;   (enotify-mode-line-remove-notification "imap"))

  )

(remove-hook 'mu4e-index-updated-hook 'mu4e-maildirs-extension-imap-notify-clear)
(add-hook 'mu4e-index-updated-hook 'mu4e-maildirs-extension-imap-notify-clear)

(provide 'mu4e-maildirs-extension)
;;; mu4e-maildirs-extension.el ends here
