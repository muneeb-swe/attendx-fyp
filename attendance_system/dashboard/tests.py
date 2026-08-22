from django.test import TestCase, Client
from django.utils import timezone

from users.models import User, Student, Teacher, Device, DeviceEvent
from attendance.models import Class, Enrollment, Session, AttendanceRecord


class DashboardTestBase(TestCase):
    """Common fixtures: an admin user, a plain student/teacher (to prove
    they're locked out), and one class/session/record for the drill-down
    tests."""

    def setUp(self):
        self.client = Client()

        self.admin_user = User.objects.create_user(
            username='admin1', password='pass123', role='admin'
        )
        self.student_user = User.objects.create_user(
            username='student1', password='pass123', role='student'
        )
        self.student = Student.objects.create(
            user=self.student_user, roll_number='CS-101', department='CS', batch='2026'
        )
        self.teacher_user = User.objects.create_user(
            username='teacher1', password='pass123', role='teacher'
        )
        self.teacher = Teacher.objects.create(
            user=self.teacher_user, department='CS', employee_id='EMP1'
        )

        self.class_obj = Class.objects.create(
            name='Data Structures', subject='CS201', teacher=self.teacher
        )
        Enrollment.objects.create(student=self.student, class_enrolled=self.class_obj)


class AccessControlTests(DashboardTestBase):
    """The admin_required decorator is the whole security model for this
    app — every one of these must hold."""

    def test_anonymous_user_redirected_to_login(self):
        response = self.client.get('/dashboard/')
        self.assertEqual(response.status_code, 302)
        self.assertIn('/dashboard/login/', response.url)

    def test_student_account_cannot_access_dashboard(self):
        self.client.login(username='student1', password='pass123')
        response = self.client.get('/dashboard/')
        self.assertEqual(response.status_code, 302)

    def test_teacher_account_cannot_access_dashboard(self):
        self.client.login(username='teacher1', password='pass123')
        response = self.client.get('/dashboard/')
        self.assertEqual(response.status_code, 302)

    def test_admin_account_can_access_dashboard(self):
        self.client.login(username='admin1', password='pass123')
        response = self.client.get('/dashboard/')
        self.assertEqual(response.status_code, 200)

    def test_login_view_rejects_non_admin_credentials(self):
        response = self.client.post('/dashboard/login/', {
            'username': 'student1', 'password': 'pass123',
        })
        # Should NOT redirect to home — bounced back to login with an error
        self.assertEqual(response.status_code, 200)
        self.assertNotIn('_auth_user_id', self.client.session)

    def test_login_view_accepts_admin_credentials(self):
        response = self.client.post('/dashboard/login/', {
            'username': 'admin1', 'password': 'pass123',
        })
        self.assertEqual(response.status_code, 302)
        self.assertIn('/dashboard/', response.url)

    def test_logout_clears_session(self):
        self.client.login(username='admin1', password='pass123')
        self.client.get('/dashboard/logout/')
        response = self.client.get('/dashboard/')
        self.assertEqual(response.status_code, 302)


class OverviewStatsTests(DashboardTestBase):
    def setUp(self):
        super().setUp()
        self.client.login(username='admin1', password='pass123')

        self.session = Session.objects.create(
            class_ref=self.class_obj, teacher=self.teacher,
            qr_token='tok', expires_at=timezone.now(), is_active=False, is_submitted=True,
        )

    def test_present_with_and_without_proof_split_correctly(self):
        # Present WITH a signature (real scan)
        AttendanceRecord.objects.create(
            session=self.session, student=self.student, status='present',
            original_status='present', signature='real-signature-abc',
        )
        # Present with NO signature (pure manual add by a teacher)
        other_user = User.objects.create_user(username='s2', password='pass123', role='student')
        other_student = Student.objects.create(user=other_user, roll_number='CS-102', department='CS', batch='2026')
        AttendanceRecord.objects.create(
            session=self.session, student=other_student, status='present',
            original_status='absent', signature='', is_modified=True,
        )
        # Absent record — should NOT count toward either present bucket
        third_user = User.objects.create_user(username='s3', password='pass123', role='student')
        third_student = Student.objects.create(user=third_user, roll_number='CS-103', department='CS', batch='2026')
        AttendanceRecord.objects.create(
            session=self.session, student=third_student, status='absent',
            original_status='absent', signature='',
        )

        response = self.client.get('/dashboard/')
        self.assertEqual(response.context['present_with_proof'], 1)
        self.assertEqual(response.context['present_without_proof'], 1)
        self.assertEqual(response.context['absent'], 1)

    def test_absent_to_present_and_present_to_absent_counts(self):
        AttendanceRecord.objects.create(
            session=self.session, student=self.student, status='present',
            original_status='absent', is_modified=True, signature='',
        )
        response = self.client.get('/dashboard/')
        self.assertEqual(response.context['absent_to_present'], 1)
        self.assertEqual(response.context['present_to_absent'], 0)


class DeviceListTests(DashboardTestBase):
    def setUp(self):
        super().setUp()
        self.client.login(username='admin1', password='pass123')

    def test_lists_enrolled_devices(self):
        Device.objects.create(student=self.student, public_key='k', device_fingerprint='fp1')
        response = self.client.get('/dashboard/devices/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.context['page_obj']), 1)

    def test_search_by_roll_number_filters_results(self):
        Device.objects.create(student=self.student, public_key='k', device_fingerprint='fp1')
        response = self.client.get('/dashboard/devices/', {'q': 'CS-101'})
        self.assertEqual(len(response.context['page_obj']), 1)

        response = self.client.get('/dashboard/devices/', {'q': 'NO-MATCH'})
        self.assertEqual(len(response.context['page_obj']), 0)

    def test_status_filter_active_vs_disabled(self):
        Device.objects.create(student=self.student, public_key='k', device_fingerprint='fp1', is_active=True)
        response = self.client.get('/dashboard/devices/', {'status': 'disabled'})
        self.assertEqual(len(response.context['page_obj']), 0)

        response = self.client.get('/dashboard/devices/', {'status': 'active'})
        self.assertEqual(len(response.context['page_obj']), 1)

    def test_never_enrolled_view_shows_students_with_no_device(self):
        # self.student has no device at all
        response = self.client.get('/dashboard/devices/', {'never_enrolled': '1'})
        self.assertIn(self.student, response.context['never_enrolled'])


class DeviceToggleTests(DashboardTestBase):
    def setUp(self):
        super().setUp()
        self.client.login(username='admin1', password='pass123')
        self.device = Device.objects.create(
            student=self.student, public_key='k', device_fingerprint='fp1', is_active=True
        )

    def test_disable_flips_state_and_logs_event(self):
        self.client.post(f'/dashboard/devices/{self.device.id}/toggle/')
        self.device.refresh_from_db()
        self.assertFalse(self.device.is_active)

        event = DeviceEvent.objects.get(device=self.device, event_type='deactivated')
        self.assertEqual(event.performed_by, self.admin_user)

    def test_enable_flips_state_and_logs_event(self):
        self.device.is_active = False
        self.device.save()

        self.client.post(f'/dashboard/devices/{self.device.id}/toggle/')
        self.device.refresh_from_db()
        self.assertTrue(self.device.is_active)

        event = DeviceEvent.objects.get(device=self.device, event_type='reactivated')
        self.assertEqual(event.performed_by, self.admin_user)

    def test_enable_blocked_by_integrity_error_does_not_crash(self):
        """
        If enabling this device would violate the one-active-device-per-
        student or one-active-fingerprint constraint, the view must
        catch that and show an error, not 500.
        """
        self.device.is_active = False
        self.device.save()

        # Give the student a DIFFERENT active device — enabling the
        # first one back should now violate one_active_device_per_student
        Device.objects.create(
            student=self.student, public_key='k2', device_fingerprint='fp2', is_active=True
        )

        response = self.client.post(f'/dashboard/devices/{self.device.id}/toggle/', follow=True)
        self.assertEqual(response.status_code, 200)  # no 500
        self.device.refresh_from_db()
        self.assertFalse(self.device.is_active)  # still disabled — enable failed safely

    def test_get_request_does_not_toggle(self):
        """Toggling must be POST-only — a GET (e.g. a link click, a
        prefetch, a crawler) must never flip device state."""
        self.client.get(f'/dashboard/devices/{self.device.id}/toggle/')
        self.device.refresh_from_db()
        self.assertTrue(self.device.is_active)  # unchanged


class ClassAndSessionDrilldownTests(DashboardTestBase):
    """The main feature: Classes -> Sessions -> per-student proof table."""

    def setUp(self):
        super().setUp()
        self.client.login(username='admin1', password='pass123')
        self.session = Session.objects.create(
            class_ref=self.class_obj, teacher=self.teacher,
            qr_token='tok', expires_at=timezone.now(), is_active=False, is_submitted=True,
        )

    def test_class_list_shows_enrolled_and_session_counts(self):
        response = self.client.get('/dashboard/classes/')
        row = response.context['classes'][0]
        self.assertEqual(row['enrolled_count'], 1)
        self.assertEqual(row['session_count'], 1)

    def test_class_detail_shows_per_session_counts(self):
        AttendanceRecord.objects.create(
            session=self.session, student=self.student, status='present',
            original_status='present', signature='sig',
        )
        response = self.client.get(f'/dashboard/classes/{self.class_obj.id}/')
        row = response.context['sessions'][0]
        self.assertEqual(row['present'], 1)
        self.assertEqual(row['absent'], 0)

    def test_session_detail_shows_original_vs_current_and_signature(self):
        """
        This is the exact scenario from the feature request: a student
        marked attendance (original='present', has a signature) but a
        teacher changed it to absent. The session detail page must show
        both the original proof AND the current status.
        """
        AttendanceRecord.objects.create(
            session=self.session, student=self.student, status='absent',
            original_status='present', signature='real-signature-proof',
            is_modified=True,
        )
        response = self.client.get(f'/dashboard/sessions/{self.session.id}/')
        record = list(response.context['records'])[0]
        self.assertEqual(record.original_status, 'present')
        self.assertEqual(record.status, 'absent')
        self.assertTrue(record.signature)
        self.assertTrue(record.is_modified)

    def test_nonexistent_class_returns_404(self):
        response = self.client.get('/dashboard/classes/99999/')
        self.assertEqual(response.status_code, 404)

    def test_nonexistent_session_returns_404(self):
        response = self.client.get('/dashboard/sessions/99999/')
        self.assertEqual(response.status_code, 404)


class EventLogTests(DashboardTestBase):
    def setUp(self):
        super().setUp()
        self.client.login(username='admin1', password='pass123')

    def test_filters_by_event_type(self):
        DeviceEvent.objects.create(student=self.student, event_type='enrolled', device_fingerprint='fp1')
        DeviceEvent.objects.create(student=self.student, event_type='deactivated', device_fingerprint='fp1')

        response = self.client.get('/dashboard/events/', {'type': 'enrolled'})
        self.assertEqual(len(response.context['page_obj']), 1)

    def test_search_by_roll_number(self):
        DeviceEvent.objects.create(student=self.student, event_type='enrolled', device_fingerprint='fp1')
        response = self.client.get('/dashboard/events/', {'q': 'CS-101'})
        self.assertEqual(len(response.context['page_obj']), 1)

        response = self.client.get('/dashboard/events/', {'q': 'NO-MATCH'})
        self.assertEqual(len(response.context['page_obj']), 0)
